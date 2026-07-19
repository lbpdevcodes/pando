# frozen_string_literal: true

require "charming/test_helper"
require "tmpdir"

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

  it "quits through the command palette" do
    keyring = create_profile!
    Pando::Store.data_key = keyring.data_key
    seed_conversation
    Pando::Store.lock!

    backend = run_journey(*unlock_keys, "ctrl+p", *"quit".chars, "enter")

    expect(backend.frames.any? { |frame| plain(frame).include?("Quit app") }).to be true
  end
end
