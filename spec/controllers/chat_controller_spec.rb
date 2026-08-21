# frozen_string_literal: true

require "charming/test_helper"
require "tmpdir"

# Controller-level regression specs for charming 0.4.0's persistent
# controllers: one instance serves every dispatch, so data memos from a
# previous dispatch must be expired or mutated rows never repaint.
RSpec.describe Pando::ChatController do
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
    keyring
  end

  def seed_conversation(title: "Alice")
    Pando::Conversation.create!(key: "dm:test:#{title.downcase}", title: title,
      last_activity_at: Time.now.utc)
  end

  def build_chat
    build_controller(Pando::ChatController, app: Pando::Application.new)
  end

  def frame_of(response)
    Charming::UI::Width.strip_ansi(response.body.to_s)
  end

  it "repaints a badge changed behind the controller's back between dispatches" do
    create_profile!
    seed_conversation(title: "Alice") # active; Zoe stays unopened
    zoe = Pando::Conversation.create!(key: "dm:test:zoe", title: "Zoe",
      last_activity_at: Time.now.utc - 600)
    ctrl = build_chat

    press(ctrl, "end") # first render; memoizes the conversation rows
    zoe.update!(unread_count: 5) # a different AR instance, as ingest would use
    response = press(ctrl, "end")

    expect(frame_of(response)).to include("Zoe (5)")
  end

  it "keeps a per-conversation composer draft across a switch" do
    create_profile!
    seed_conversation(title: "Alice")
    Pando::Conversation.create!(key: "dm:test:zoe", title: "Zoe",
      last_activity_at: Time.now.utc - 600)
    ctrl = build_chat

    press(ctrl, "tab") # sidebar → composer
    "draft-a".each_char { |char| press(ctrl, char) }
    press_sequence(ctrl, ["tab", "j", "enter"]) # activate Zoe
    expect(frame_of(press(ctrl, "end"))).not_to include("draft-a")

    "b".each_char { |char| press(ctrl, char) }
    press_sequence(ctrl, ["tab", "k", "enter"]) # back to Alice

    frame = frame_of(press(ctrl, "end"))
    expect(frame).to include("draft-a")
  end

  it "clears the composer after a send" do
    create_profile!
    seed_conversation(title: "Alice")
    ctrl = build_chat

    press(ctrl, "tab")
    "hello".each_char { |char| press(ctrl, char) }
    response = press(ctrl, "enter")

    frame = frame_of(response)
    expect(frame).to include("you: hello")
    expect(frame).to include("Message Alice…") # empty composer shows the placeholder
  end

  it "reopens the add-contact modal with an empty input" do
    keyring = create_profile!
    seed_conversation(title: "Alice")
    ctrl = build_chat
    ctrl.session[:identity] = keyring.identity # what unlock would set

    account = Pando::Crypto::Account.generate
    device = Pando::Crypto::Device.generate
    bundle = Pando::Crypto::DeviceBundle.issue(device: device, account: account)
    code = Pando::Invite.encode(bundle: bundle.to_h, name: "Zoe")

    ctrl.open_add_contact
    press_sequence(ctrl, [*"bad code".chars, "enter"]) # malformed: cleared, stays open
    ctrl.open_add_contact
    press_sequence(ctrl, [*code.chars, "enter"]) # valid: added, modal closes

    ctrl.open_add_contact
    expect(frame_of(press(ctrl, "end"))).to include("paste an invite code")
  end
end
