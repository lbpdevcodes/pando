# frozen_string_literal: true

RSpec.describe Pando::Crypto::SealedTransfer do
  it "seals an account seed so only the target device can open it" do
    account = Pando::Crypto::Account.generate
    device = Pando::Crypto::Device.generate

    sealed = described_class.seal(account.seed, to: device.encryption_public_key)
    restored = Pando::Crypto::Account.from_seed(described_class.open(sealed, with: device))

    expect(restored.fingerprint).to eq(account.fingerprint)
  end

  it "cannot be opened by a different device" do
    sealed = described_class.seal(Pando::Crypto::Account.generate.seed,
      to: Pando::Crypto::Device.generate.encryption_public_key)

    expect { described_class.open(sealed, with: Pando::Crypto::Device.generate) }
      .to raise_error(RbNaCl::CryptoError)
  end
end
