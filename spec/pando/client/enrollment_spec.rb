# frozen_string_literal: true

RSpec.describe Pando::Client::Enrollment do
  # The relay's in-memory Rendezvous, adapted to the RendezvousClient duck —
  # the enrollment logic never knows whether HTTP is underneath.
  let(:rendezvous_adapter) do
    slots = Pando::Relay::Rendezvous.new
    Class.new do
      define_method(:deposit) { |code, payload| slots.deposit(code, payload, now: Time.now.to_i) }
      define_method(:fetch) { |code| slots.fetch(code, now: Time.now.to_i) }
      define_method(:delete) { |code| slots.delete(code) }
    end.new
  end

  let(:account) { Pando::Crypto::Account.generate }
  let(:enrolled_device) { Pando::Crypto::Device.generate }
  let(:identity) { Pando::Crypto::Identity.to_h(account: account, device: enrolled_device) }

  it "round-trips the account seed and import blob through offer and grant" do
    offer = described_class::Offer.new(rendezvous: rendezvous_adapter)
    offer.deposit!
    expect(offer.code).to match(/\A\d{6}\z/)
    expect(offer.poll).to eq(:waiting)

    granter = described_class::Grant.new(identity: identity, rendezvous: rendezvous_adapter)
    pending_offer = granter.fetch_offer(offer.code)
    expect(pending_offer).not_to be_nil
    expect(granter.safety_code(pending_offer)).to eq(offer.safety_code)

    granter.approve!(pending_offer, code: offer.code,
      contacts: [{"fp" => "aaaa000011112222", "name" => "Zoe", "bundles" => []}],
      conversations: [{"key" => "room:x", "kind" => "room", "title" => "trio",
                       "members" => ["aaaa000011112222"]}])

    result = offer.poll
    expect(result).to be_a(Hash)
    new_account = Pando::Crypto::Identity.account_from(result[:identity])
    expect(new_account.fingerprint).to eq(account.fingerprint)
    expect(result[:import]["contacts"].sole["name"]).to eq("Zoe")
    expect(result[:import]["own_devices"]).not_to be_empty

    # The new device's identity carries ITS device keys, not the granter's.
    new_device = Pando::Crypto::Identity.device_from(result[:identity])
    expect(new_device.mailbox).to eq(offer.device.mailbox)
  end

  it "reports denial when the approver deletes the slot" do
    offer = described_class::Offer.new(rendezvous: rendezvous_adapter)
    offer.deposit!

    described_class::Grant.new(identity: identity, rendezvous: rendezvous_adapter)
      .deny!(offer.code)

    expect(offer.poll).to eq(:denied)
  end

  it "never grants to a mismatched safety code (the human checks, we expose it)" do
    offer = described_class::Offer.new(rendezvous: rendezvous_adapter)
    offer.deposit!
    granter = described_class::Grant.new(identity: identity, rendezvous: rendezvous_adapter)
    pending_offer = granter.fetch_offer(offer.code)

    expect(pending_offer["safety"]).to eq(offer.safety_code)
    expect(granter.safety_code(pending_offer)).to eq(pending_offer["safety"])
  end
end
