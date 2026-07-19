# frozen_string_literal: true

RSpec.describe Pando::CreateRoom do
  it "creates a room of one with the creator as sole participant" do
    room = described_class.new(my_fingerprint: "aaaa000011112222").call(name: "design team")

    expect(room.kind).to eq("room")
    expect(room.display_title).to eq("design team")
    expect(room.key).to start_with("room:")
    expect(room.room_participants.pluck(:fingerprint)).to eq(["aaaa000011112222"])
    expect(room.membership_updated_at).not_to be_nil
  end
end
