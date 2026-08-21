# frozen_string_literal: true

require "charming/test_helper"
require "tmpdir"

# A recorder double that "captures" fixture bytes instead of spawning a real
# process; journeys drive the full UI around it.
FAKE_JOURNEY_RECORDER = Class.new do
  attr_reader :path, :cancelled

  def initialize(bytes) = (@bytes = bytes)

  def start(path) = (@path = path) && (@recording = true)

  def stop
    File.binwrite(@path, @bytes) if @recording
    @recording = false
  end

  def cancel
    @recording = false
    FileUtils.rm_f(@path.to_s)
    @cancelled = true
  end

  def recording? = !!@recording

  def elapsed = 7
end

# Full end-to-end journeys: a real Runtime driving the whole app through a
# MemoryBackend, exactly as a user at a keyboard would.
RSpec.describe "Pando journeys" do
  include Charming::TestHelper

  let(:passphrase) { "letmein" }

  around do |example|
    Dir.mktmpdir do |dir|
      ENV["PANDO_ROOT"] = dir
      example.run
    ensure
      ENV.delete("PANDO_ROOT")
    end
  end

  def create_profile!
    keyring = Pando::Store::Keyring.create(
      path: Pando::Store.keyring_path, passphrase: passphrase,
      identity: Pando::Crypto::Identity.generate,
      params: {opslimit: :interactive, memlimit: :interactive}
    )
    Pando::Store.data_key = keyring.data_key
    Pando::Store.lock!
    keyring
  end

  def seed_conversation(title: "Alice", bodies: ["first message", "second message"])
    conversation = Pando::Conversation.create!(key: "dm:test:#{title.downcase}", title: title,
      last_activity_at: Time.now.utc)
    bodies.each_with_index do |body, index|
      conversation.messages.create!(direction: "incoming", body: body, status: "sent",
        sent_at: Time.now.utc - (bodies.length - index) * 60, content_id: "msg-#{title}-#{index}")
    end
    conversation
  end

  def run_journey(*keys, width: 100, height: 30)
    Pando::Store.lock! # every journey starts at the passphrase prompt
    backend = memory_backend(*keys, width: width, height: height)
    Charming::Runtime.new(Pando::Application.new, backend: backend,
      task_executor: Charming::Tasks::InlineExecutor).run
    backend
  end

  def plain(frame)
    Charming::UI::Width.strip_ansi(frame.to_s)
  end

  def unlock_keys
    [*passphrase.chars, "enter"]
  end

  it "boots locked into onboarding" do
    create_profile!
    backend = run_journey("ctrl+c")

    expect(plain(backend.frames.first)).to include("Enter your passphrase")
  end

  it "offers profile creation when no keyring exists" do
    backend = run_journey("ctrl+c")

    expect(plain(backend.frames.first)).to include("Choose a passphrase for your new profile")
  end

  it "rejects a wrong passphrase with a visible error" do
    create_profile!
    backend = run_journey(*"wrong".chars, "enter", "ctrl+c")

    expect(plain(backend.frames.last)).to include("Wrong passphrase")
  end

  it "unlocks into the conversation list and transcript" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    seed_conversation
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "q")
    frame = plain(backend.frames.last)

    expect(frame).to include("Alice")
    expect(frame).to include("second message")
  end

  it "sends a message from the composer" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    seed_conversation
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "tab", *"hi there".chars, "enter", "ctrl+c")

    message = Pando::Message.where(direction: "outgoing").last
    expect(message).not_to be_nil
    expect(message.body).to eq("hi there")
    expect(message.status).to eq("pending")
    expect(plain(backend.frames.last)).to include("hi there")
  end

  it "follows the newest messages and holds position when scrolled up" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    seed_conversation(bodies: (1..60).map { |n| "note number #{n.to_s.rjust(2, "0")}" })
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "page_up", "end", "q")
    frames = backend.frames.map { |frame| plain(frame) }

    landed = frames.index { |frame| frame.include?("note number 60") }
    expect(landed).not_to be_nil, "transcript never followed to the newest message"
    scrolled = frames[landed..].index { |frame| !frame.include?("note number 60") }
    expect(scrolled).not_to be_nil, "page_up never left the bottom"
    expect(frames.last).to include("note number 60")
  end

  it "adds a contact from an invite code through the palette" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    Pando::Store.lock!

    account = Pando::Crypto::Account.generate
    device = Pando::Crypto::Device.generate
    bundle = Pando::Crypto::DeviceBundle.issue(device: device, account: account)
    code = Pando::Invite.encode(bundle: bundle.to_h, name: "Zoe")

    backend = run_journey(*unlock_keys, "ctrl+p", *"add contact".chars, "enter", *code.chars, "enter", "ctrl+c")

    contact = Pando::Contact.find_by(fingerprint: account.fingerprint)
    expect(contact).not_to be_nil
    expect(contact.display_name).to eq("Zoe")
    expect(Pando::Conversation.where(kind: "dm").count).to eq(1)
    expect(plain(backend.frames.last)).to include("Added Zoe")
  end

  it "opens a modal from the palette with the palette fully dismissed" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    seed_conversation
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "ctrl+p", *"add contact".chars, "enter", "ctrl+c")

    frames = backend.frames.map { |f| plain(f) }
    expect(frames.none? { |f| f.include?("DoubleRenderError") }).to be(true),
      "a palette command double-rendered: #{frames.find { |f| f.include?("DoubleRenderError") }}"
    expect(frames.last).to include("Add contact")
    expect(frames.last).not_to include("Search commands")
  end

  it "tells the user the contact request sends on reconnect when adding offline" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    Pando::Store.lock!

    account = Pando::Crypto::Account.generate
    device = Pando::Crypto::Device.generate
    bundle = Pando::Crypto::DeviceBundle.issue(device: device, account: account)
    code = Pando::Invite.encode(bundle: bundle.to_h, name: "Zoe")

    backend = run_journey(*unlock_keys, "ctrl+p", *"add contact".chars, "enter", *code.chars, "enter", "ctrl+c")

    expect(plain(backend.frames.last)).to include("your contact request sends when you reconnect")
    expect(Pando::ContactRequest.count).to eq(0)
  end

  def seed_contact_request(name: "Zoe")
    account = Pando::Crypto::Account.generate
    device = Pando::Crypto::Device.generate
    bundle = Pando::Crypto::DeviceBundle.issue(device: device, account: account)
    Pando::ContactRequest.create!(fingerprint: account.fingerprint, direction: "incoming",
      name: name, bundle: JSON.generate(bundle.to_h), status: "pending",
      content_id: SecureRandom.uuid)
  end

  it "accepts a contact request from the inbox" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    request = seed_contact_request
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "ctrl+p", *"contact requests".chars, "enter", "a", "ctrl+c")

    expect(request.reload.status).to eq("accepted")
    contact = Pando::Contact.find_by(fingerprint: request.fingerprint)
    expect(contact.display_name).to eq("Zoe")
    expect(Pando::Conversation.where(kind: "dm").count).to eq(1)
    expect(backend.frames.map { |f| plain(f) }.join).to include("Zoe")
  end

  it "declines a contact request without creating a contact" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    request = seed_contact_request
    Pando::Store.lock!

    run_journey(*unlock_keys, "ctrl+p", *"contact requests".chars, "enter", "d", "ctrl+c")

    expect(request.reload.status).to eq("declined")
    expect(Pando::Contact.count).to eq(0)
  end

  it "shows a pending contact request badge in the sidebar" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    seed_contact_request
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "q")

    expect(plain(backend.frames.last)).to include("! 1 request")
  end

  it "toggles directory discoverability from the palette" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "ctrl+p", *"discover".chars, "enter", "ctrl+c")

    expect(Pando::Setting.get("discoverable")).to eq("1")
    expect(plain(backend.frames.last)).to include("discoverable by fingerprint")
  end

  it "rejects a malformed fingerprint in the find-contact modal" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "ctrl+p", *"find contact".chars, "enter",
      *"nope".chars, "enter", "ctrl+c")

    expect(plain(backend.frames.last)).to include("16-hex")
    expect(Pando::ContactRequest.count).to eq(0)
  end

  it "walks a contact through verified, key-changed, and re-verified" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    my_fingerprint = Pando::Crypto::Identity.account_from(keyring.identity).fingerprint
    account = Pando::Crypto::Account.generate
    device = Pando::Crypto::Device.generate
    bundle = Pando::Crypto::DeviceBundle.issue(device: device, account: account)
    invite = Pando::Invite.decode(Pando::Invite.encode(bundle: bundle.to_h, name: "Zoe"))
    contact, = Pando::AddContact.new(my_fingerprint: my_fingerprint).call(invite)
    Pando::Store.lock!

    # Verify: fingerprints modal → enter marks verified, sidebar shows the badge.
    backend = run_journey(*unlock_keys, "ctrl+p", *"verify".chars, "enter", "enter", "q")
    expect(contact.reload.trust_level).to eq("verified")
    frames = backend.frames.map { |frame| plain(frame) }
    expect(frames.join).to include(contact.fingerprint.scan(/.{4}/).join(" "))
    expect(frames.last).to include("Zoe \u{2713}")

    # A key change raises the banner and downgrades the badge.
    Pando::Store.data_key = keyring.data_key
    contact.update!(trust_level: "key_changed")
    Pando::Store.lock!
    backend = run_journey(*unlock_keys, "q")
    frame = plain(backend.frames.last)
    expect(frame).to include("key has changed")
    expect(frame).to include("Zoe !")

    # Re-verifying clears the banner.
    backend = run_journey(*unlock_keys, "ctrl+p", *"verify".chars, "enter", "enter", "q")
    expect(contact.reload.trust_level).to eq("verified")
    expect(plain(backend.frames.last)).not_to include("key has changed")
  end

  it "creates a room from the palette and lands in it" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "ctrl+p", *"new room".chars, "enter",
      *"design crew".chars, "enter", "ctrl+c")

    room = Pando::Conversation.find_by(kind: "room")
    expect(room.display_title).to eq("design crew")
    expect(room.room_participants.count).to eq(1)
    frame = plain(backend.frames.last)
    expect(frame).to include("design crew")
    expect(frame).to include("1 members")
  end

  it "refuses to invite into a conversation that is not a room" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    seed_conversation
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "ctrl+p", *"invite to room".chars, "enter", "ctrl+c")

    expect(plain(backend.frames.last)).to include("isn't a room")
  end

  it "adds a relay with a token and keeps it across restarts" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    Pando::Store.lock!

    run_journey(*unlock_keys, "ctrl+p", *"add relay".chars, "enter",
      *"http://relay.example:9999".chars, "enter", *"hunter2".chars, "enter", "ctrl+c")

    relay = Pando::RelayConfig.active_relay
    expect(relay.url).to eq("http://relay.example:9999")
    expect(relay.token).to eq("hunter2")

    # A second full app run (fresh Runtime) still lists the saved relay.
    backend = run_journey(*unlock_keys, "ctrl+p", *"switch relay".chars, "enter", "ctrl+c")
    expect(plain(backend.frames.last)).to include("relay.example")
  end

  it "switches the active relay from the picker" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    first = Pando::RelayConfig.create!(name: "one", url: "http://one.example:1", active: true)
    second = Pando::RelayConfig.create!(name: "two", url: "http://two.example:2")
    Pando::Store.lock!

    run_journey(*unlock_keys, "ctrl+p", *"switch relay".chars, "enter", "j", "enter", "ctrl+c")

    expect(first.reload.active).to be(false)
    expect(second.reload.active).to be(true)
  end

  it "rejects an invalid relay url" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "ctrl+p", *"add relay".chars, "enter",
      *"not a url".chars, "enter", "ctrl+c")

    expect(Pando::RelayConfig.count).to eq(0)
    expect(plain(backend.frames.last)).to include("http://host:8787")
  end

  it "attaches a file through the picker and stores it sealed" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    seed_conversation
    Pando::Store.lock!

    Dir.mktmpdir do |files_dir|
      ENV["PANDO_ATTACH_ROOT"] = files_dir
      File.binwrite(File.join(files_dir, "note.txt"), "attach me please")

      backend = run_journey(*unlock_keys, "ctrl+p", *"attach file".chars, "enter",
        "enter", "ctrl+c")

      message = Pando::Message.find_by(kind: "attachment")
      expect(message.body).to eq("note.txt")
      attachment = message.attachment
      expect(attachment.status).to eq("sending")
      expect(Pando::Attachments::BlobStore.new.read(attachment.attachment_id))
        .to eq("attach me please")
      expect(plain(backend.frames.last)).to include("note.txt")
    ensure
      ENV.delete("PANDO_ATTACH_ROOT")
    end
  end

  it "renders received attachments as file lines and saves them on demand" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    conversation = seed_conversation
    message = conversation.messages.create!(direction: "incoming", kind: "attachment",
      body: "photo.png", status: "delivered", sent_at: Time.now.utc, content_id: "att-m1")
    Pando::Attachment.create!(message: message, attachment_id: "att-1",
      name: "photo.png", mime: "image/png", size: 12, digest: "d", total_chunks: 1,
      received_chunks: 1, status: "complete")
    Pando::Attachments::BlobStore.new.write("att-1", "png-ish bytes")
    Pando::Store.lock!

    Dir.mktmpdir do |downloads|
      ENV["PANDO_DOWNLOADS"] = downloads

      backend = run_journey(*unlock_keys, "ctrl+p", *"save attachment".chars, "enter", "ctrl+c")

      frame_text = backend.frames.map { |f| plain(f) }.join
      expect(frame_text).to include("photo.png (12 B)")
      saved = File.join(downloads, "photo.png")
      expect(File.binread(saved)).to eq("png-ish bytes")
      expect(plain(backend.frames.last)).to include("Saved to")
    ensure
      ENV.delete("PANDO_DOWNLOADS")
    end
  end

  def with_fake_recorder(bytes: "RIFFfake-wav-bytesWAVE")
    recorder = FAKE_JOURNEY_RECORDER.new(bytes)
    Pando::Audio.recorder_factory = -> { recorder }
    yield recorder
  ensure
    Pando::Audio.recorder_factory = nil
  end

  it "records a voice note and sends it as a voice attachment" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    seed_conversation
    Pando::Store.lock!

    with_fake_recorder do |recorder|
      backend = run_journey(*unlock_keys, "ctrl+r", "ctrl+r", "ctrl+c")

      message = Pando::Message.find_by(kind: "attachment")
      expect(message).not_to be_nil
      attachment = message.attachment
      expect(attachment.voice).to be(true)
      expect(attachment.duration_s).to eq(7)
      expect(Pando::Attachments::BlobStore.new.read(attachment.attachment_id))
        .to eq("RIFFfake-wav-bytesWAVE")
      expect(File.exist?(recorder.path)).to be(false)
      expect(backend.frames.map { |f| plain(f) }.join).to include("REC 0:07")
    end
  end

  it "discards a cancelled recording without sending anything" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    seed_conversation
    Pando::Store.lock!

    with_fake_recorder do |recorder|
      backend = run_journey(*unlock_keys, "ctrl+r", "escape", "ctrl+c")

      expect(recorder.cancelled).to be(true)
      expect(Pando::Message.where(kind: "attachment")).to be_empty
      expect(plain(backend.frames.last)).to include("discarded")
    end
  end

  def with_fake_rendezvous
    slots = Pando::Relay::Rendezvous.new
    adapter = Class.new do
      define_method(:deposit) { |code, payload| slots.deposit(code, payload, now: Time.now.to_i) }
      define_method(:fetch) { |code| slots.fetch(code, now: Time.now.to_i) }
      define_method(:delete) { |code| slots.delete(code) }
    end.new
    Pando::Client::Enrollment.rendezvous_factory = ->(_url, _token) { adapter }
    yield adapter
  ensure
    Pando::Client::Enrollment.rendezvous_factory = nil
  end

  it "walks a fresh device into the enrollment waiting screen" do
    with_fake_rendezvous do |rendezvous|
      backend = run_journey("ctrl+p", *"enroll this device".chars, "enter",
        *"devicepass".chars, "enter", "ctrl+c")

      frame = plain(backend.frames.last)
      expect(frame).to include("Enrolling this device")
      expect(frame).to match(/Code\s+\d{6}/)
      expect(frame).to match(/Safety code\s+\h{8}/)

      code = frame[/Code\s+(\d{6})/, 1]
      offer = rendezvous.fetch(code).sole
      expect(offer["type"]).to eq("enroll-offer")
    end
  end

  it "approves an enrolling device from the chat screen" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    my_fingerprint = Pando::Crypto::Identity.account_from(keyring.identity).fingerprint
    Pando::Store.lock!

    with_fake_rendezvous do |rendezvous|
      offer = Pando::Client::Enrollment::Offer.new(rendezvous: rendezvous)
      offer.deposit!

      backend = run_journey(*unlock_keys, "ctrl+p", *"enroll a device".chars, "enter",
        *offer.code.chars, "enter", "y", "ctrl+c")

      expect(backend.frames.map { |f| plain(f) }.join).to include(offer.safety_code)
      result = offer.poll
      expect(result).to be_a(Hash)
      expect(Pando::Crypto::Identity.account_from(result[:identity]).fingerprint)
        .to eq(my_fingerprint)
      expect(Pando::ContactDevice.find_by(mailbox: offer.device.mailbox).fingerprint)
        .to eq(my_fingerprint)
    end
  end

  it "denies an enrolling device with n" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    Pando::Store.lock!

    with_fake_rendezvous do |rendezvous|
      offer = Pando::Client::Enrollment::Offer.new(rendezvous: rendezvous)
      offer.deposit!

      run_journey(*unlock_keys, "ctrl+p", *"enroll a device".chars, "enter",
        *offer.code.chars, "enter", "n", "ctrl+c")

      expect(offer.poll).to eq(:denied)
    end
  end

  it "cycles the message timer and hides expired messages" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    conversation = seed_conversation
    conversation.messages.create!(direction: "incoming", body: "already vanished",
      status: "delivered", sent_at: Time.now.utc - 120, content_id: "expired-1",
      expires_at: Time.now.utc - 1)
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "ctrl+p", *"message timer".chars, "enter", "ctrl+c")

    expect(conversation.reload.ttl).to eq(300)
    frame = plain(backend.frames.last)
    expect(frame).to include("Message timer: 5 minutes")
    expect(frame).to include("5m")
    expect(frame).not_to include("already vanished")
    expect(frame).to include("second message")
  end

  it "shows the invite QR fallback text without graphics" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "ctrl+p", "q", "r", "enter", "ctrl+c")

    frame = backend.frames.map { |f| plain(f) }.join("\n")
    expect(frame).to include("share this code")
    identity = Pando::Store::Keyring.open(path: Pando::Store.keyring_path,
      passphrase: passphrase).identity
    account = Pando::Crypto::Identity.account_from(identity)
    device = Pando::Crypto::Identity.device_from(identity)
    code = Pando::Invite.encode(
      bundle: Pando::Crypto::DeviceBundle.issue(device: device, account: account).to_h,
      name: "me"
    )
    expect(frame.gsub(/\s+/, "")).to include(code[0, 40])
  end

  it "adds a contact from an invite file through the picker" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    Pando::Store.lock!

    account = Pando::Crypto::Account.generate
    device = Pando::Crypto::Device.generate
    bundle = Pando::Crypto::DeviceBundle.issue(device: device, account: account)
    code = Pando::Invite.encode(bundle: bundle.to_h, name: "Zoe")

    Dir.mktmpdir do |files_dir|
      ENV["PANDO_ATTACH_ROOT"] = files_dir
      File.write(File.join(files_dir, "invite.txt"), code)

      run_journey(*unlock_keys, "ctrl+p", *"load invite".chars, "enter", "enter", "ctrl+c")

      contact = Pando::Contact.find_by(fingerprint: account.fingerprint)
      expect(contact.display_name).to eq("Zoe")
      expect(Pando::Conversation.where(kind: "dm").count).to eq(1)
    ensure
      ENV.delete("PANDO_ATTACH_ROOT")
    end
  end

  it "warns when the picked file is not an invite" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    Pando::Store.lock!

    Dir.mktmpdir do |files_dir|
      ENV["PANDO_ATTACH_ROOT"] = files_dir
      File.write(File.join(files_dir, "junk.txt"), "definitely not an invite")

      backend = run_journey(*unlock_keys, "ctrl+p", *"load invite".chars, "enter",
        "enter", "ctrl+c")

      expect(Pando::Contact.count).to eq(0)
      expect(plain(backend.frames.last)).to include("isn't an invite")
    ensure
      ENV.delete("PANDO_ATTACH_ROOT")
    end
  end

  it "opens the help overlay with ? from the sidebar and dismisses it" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    seed_conversation
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "?", "escape", "q")

    frames = backend.frames.map { |f| plain(f) }
    expect(frames.join).to include("Keyboard Shortcuts")
    expect(frames.last).not_to include("Keyboard Shortcuts")
  end

  it "types ? into the composer instead of opening help" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    seed_conversation
    Pando::Store.lock!

    run_journey(*unlock_keys, "tab", *"really?".chars, "enter", "ctrl+c")

    expect(Pando::Message.where(direction: "outgoing").sole.body).to eq("really?")
  end

  it "shows unread badges and clears them when the conversation is opened" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    seed_conversation(title: "Alice")
    quiet = Pando::Conversation.create!(key: "dm:test:zoe", title: "Zoe",
      last_activity_at: Time.now.utc - 600, unread_count: 2)
    quiet.messages.create!(direction: "incoming", body: "unseen", status: "delivered",
      sent_at: Time.now.utc - 600, content_id: "unseen-1")
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "j", "enter", "ctrl+c")

    frames = backend.frames.map { |f| plain(f) }
    expect(frames.find { |f| f.include?("Zoe") }).to include("Zoe (2)")
    expect(quiet.reload.unread_count).to eq(0)
    expect(frames.last).not_to include("Zoe (2)")
  end

  it "retries failed messages from the palette" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    conversation = seed_conversation
    failed = conversation.messages.create!(direction: "outgoing", body: "rejected once",
      status: "failed", sent_at: Time.now.utc, content_id: "fail-1")
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "ctrl+p", *"retry".chars, "enter", "ctrl+c")

    expect(failed.reload.status).to eq("pending")
    expect(plain(backend.frames.last)).to include("Retrying 1 message")
  end

  it "renders the demo seed's non-ascii transcript" do
    create_profile!
    ENV["PANDO_DEMO"] = "1"

    backend = run_journey(*unlock_keys, "q")

    frame = plain(backend.frames.last)
    expect(frame).to include("this whole app is Charming now")
    expect(frame).not_to include("CompatibilityError")
  ensure
    ENV.delete("PANDO_DEMO")
  end

  it "explains instead of silently dropping a send with no conversation" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "tab", *"hello?".chars, "enter", "ctrl+c")

    expect(Pando::Message.count).to eq(0)
    expect(plain(backend.frames.last)).to include("Add a contact first")
  end

  it "warns when a message has no reachable recipients but keeps it locally" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    Pando::Conversation.create!(key: "self:notes", title: "My invite code",
      last_activity_at: Time.now.utc)
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "tab", *"note to self".chars, "enter", "ctrl+c")

    message = Pando::Message.where(direction: "outgoing").sole
    expect(message.status).to eq("pending")
    expect(plain(backend.frames.last)).to include("No recipients")
  end

  it "quits through the command palette" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    seed_conversation
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "ctrl+p", *"quit".chars, "enter")

    expect(backend.frames.any? { |frame| plain(frame).include?("Quit app") }).to be true
  end
end
