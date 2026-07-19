# frozen_string_literal: true

RSpec.describe "Pando::Message encrypted round trip" do
  let(:conversation) { Pando::Conversation.create!(key: "dm:enc:oding") }

  it "returns decrypted text as UTF-8, not the cipher's binary" do
    conversation.messages.create!(direction: "incoming", body: "well — that's nice ☺",
      status: "delivered", sent_at: Time.now.utc, content_id: "enc-1")

    body = Pando::Message.sole.body
    expect(body).to eq("well — that's nice ☺")
    expect(body.encoding).to eq(Encoding::UTF_8)
    expect(body.valid_encoding?).to be(true)
    # Interpolation into UTF-8 literals is what the transcript does — it must
    # not raise Encoding::CompatibilityError.
    expect { "12:00 them: #{body}" }.not_to raise_error
  end
end

RSpec.describe "Pando::Message expiry" do
  let(:conversation) { Pando::Conversation.create!(key: "dm:aaaa:bbbb") }

  def seed(body, expires_at:)
    conversation.messages.create!(direction: "incoming", body: body, status: "delivered",
      sent_at: Time.now.utc, content_id: "ttl-#{body}", expires_at: expires_at)
  end

  it "scopes expired messages out of reads" do
    seed("gone", expires_at: Time.now.utc - 1)
    seed("staying", expires_at: Time.now.utc + 60)
    seed("forever", expires_at: nil)

    expect(conversation.messages.unexpired.map(&:body)).to match_array(%w[staying forever])
  end

  it "sweeps only expired rows and reports the count" do
    seed("gone", expires_at: Time.now.utc - 1)
    seed("staying", expires_at: Time.now.utc + 60)
    seed("forever", expires_at: nil)

    expect(Pando::Message.sweep_expired).to eq(1)
    expect(conversation.messages.count).to eq(2)
  end
end

RSpec.describe Pando::Message do
  def conversation
    @conversation ||= Pando::Conversation.create!(key: "dm:aaa:bbb", title: "Alice")
  end

  def create_message(body: "the secret text", sent_at: Time.now.utc)
    described_class.create!(conversation: conversation, direction: "outgoing",
      body: body, sent_at: sent_at)
  end

  it "stores only ciphertext in the database" do
    message = create_message

    raw = described_class.connection.select_value(
      "SELECT body FROM messages WHERE id = #{message.id}"
    )
    expect(raw).not_to include("the secret text")
    expect(message.reload.body).to eq("the secret text")
  end

  it "refuses to read or write while the profile is locked" do
    create_message

    key = Pando::Store.data_key
    Pando::Store.lock!
    expect { create_message }.to raise_error(Pando::Store::Locked)
    expect { described_class.last.body }.to raise_error(Pando::Store::Locked)
  ensure
    Pando::Store.data_key = key
  end

  it "orders chronologically by sent time" do
    late = create_message(body: "late", sent_at: Time.now.utc)
    early = create_message(body: "early", sent_at: Time.now.utc - 60)

    expect(described_class.chronological.to_a).to eq([early, late])
  end

  it "encrypts conversation titles too" do
    conversation

    raw = described_class.connection.select_value(
      "SELECT title FROM conversations WHERE id = #{conversation.id}"
    )
    expect(raw).not_to include("Alice")
    expect(conversation.reload.display_title).to eq("Alice")
  end
end
