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

    run_journey(*unlock_keys, "ctrl+p", *"add contact".chars, "enter", *code.chars, "enter", "ctrl+c")

    contact = Pando::Contact.find_by(fingerprint: account.fingerprint)
    expect(contact).not_to be_nil
    expect(contact.display_name).to eq("Zoe")
    expect(Pando::Conversation.where(kind: "dm").count).to eq(1)
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
