# frozen_string_literal: true

require "tmpdir"

RSpec.describe Pando::Store::Keyring do
  let(:identity) { {"account_seed" => "c2VlZA==", "mailbox" => "abc123mailbox"} }

  around do |example|
    Dir.mktmpdir { |dir| @path = File.join(dir, "keyring.json") and example.run }
  end

  def create(passphrase: "correct horse")
    described_class.create(path: @path, passphrase: passphrase, identity: identity, params: fast_params)
  end

  def fast_params
    {opslimit: :interactive, memlimit: :interactive}
  end

  it "round-trips the identity and data key through create and open" do
    created = create
    opened = described_class.open(path: @path, passphrase: "correct horse")

    expect(opened.identity).to eq(identity)
    expect(opened.data_key).to eq(created.data_key)
    expect(created.data_key.bytesize).to eq(32)
  end

  it "refuses to open with the wrong passphrase" do
    create

    expect { described_class.open(path: @path, passphrase: "wrong") }
      .to raise_error(described_class::WrongPassphrase)
  end

  it "stores no plaintext identity material on disk" do
    create

    raw = File.binread(@path)
    expect(raw).not_to include("abc123mailbox")
    expect(raw).not_to include("c2VlZA==")
  end

  it "restricts the keyring file to its owner" do
    create

    expect(File.stat(@path).mode & 0o777).to eq(0o600)
  end

  it "rekeys to a new passphrase without changing the data key" do
    created = create
    created.rekey(passphrase: "new phrase")

    expect { described_class.open(path: @path, passphrase: "correct horse") }
      .to raise_error(described_class::WrongPassphrase)

    reopened = described_class.open(path: @path, passphrase: "new phrase")
    expect(reopened.data_key).to eq(created.data_key)
    expect(reopened.identity).to eq(identity)
  end
end
