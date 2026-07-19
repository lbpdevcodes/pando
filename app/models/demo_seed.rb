# frozen_string_literal: true

module Pando
  # DemoSeed plants sample conversations after unlock so the TUI can be explored
  # before networking lands (PANDO_DEMO=1). Runs once — an existing conversation
  # means there is nothing to do.
  class DemoSeed
    SCRIPTS = {
      "Alice" => [
        ["incoming", "hey! did the ruby port work out?"],
        ["outgoing", "it did — this whole app is Charming now"],
        ["incoming", "show me when it talks to a real relay"]
      ],
      "Bob" => [
        ["incoming", "lunch tomorrow?"],
        ["outgoing", "yes — noon at the usual place"]
      ]
    }.freeze

    def self.plant
      return if Conversation.exists?

      SCRIPTS.each_with_index do |(name, lines), index|
        conversation = Conversation.create!(
          key: "dm:demo:#{name.downcase}", title: name,
          last_activity_at: Time.now.utc - index * 60
        )
        plant_messages(conversation, lines)
      end
    end

    def self.plant_messages(conversation, lines)
      lines.each_with_index do |(direction, body), index|
        conversation.messages.create!(
          direction: direction, body: body, status: (direction == "outgoing") ? "delivered" : "sent",
          sent_at: Time.now.utc - (lines.length - index) * 120,
          content_id: SecureRandom.uuid
        )
      end
    end
  end
end
