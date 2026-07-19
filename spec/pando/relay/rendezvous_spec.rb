# frozen_string_literal: true

RSpec.describe Pando::Relay::Rendezvous do
  let(:rendezvous) { described_class.new(ttl: 60) }
  let(:now) { Time.now.to_i }

  it "exchanges payloads between two parties on the same slot" do
    rendezvous.deposit("slot-1", "alice-blob", now: now)
    rendezvous.deposit("slot-1", "bob-blob", now: now)

    expect(rendezvous.fetch("slot-1", now: now)).to contain_exactly("alice-blob", "bob-blob")
  end

  it "refuses a third deposit on a slot" do
    rendezvous.deposit("slot-1", "a", now: now)
    rendezvous.deposit("slot-1", "b", now: now)

    expect { rendezvous.deposit("slot-1", "c", now: now) }.to raise_error(described_class::SlotFull)
  end

  it "expires slots after their ttl" do
    rendezvous.deposit("slot-1", "a", now: now)

    expect(rendezvous.fetch("slot-1", now: now + 61)).to be_empty
  end

  it "deletes slots on demand" do
    rendezvous.deposit("slot-1", "a", now: now)
    rendezvous.delete("slot-1")

    expect(rendezvous.fetch("slot-1", now: now)).to be_empty
  end
end
