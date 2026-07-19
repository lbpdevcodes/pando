# frozen_string_literal: true

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
