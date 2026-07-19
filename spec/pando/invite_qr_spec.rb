# frozen_string_literal: true

require "rqrcode"
require "tmpdir"

RSpec.describe "Invite QR round trip" do
  let(:account) { Pando::Crypto::Account.generate }
  let(:device) { Pando::Crypto::Device.generate }
  let(:bundle) { Pando::Crypto::DeviceBundle.issue(device: device, account: account) }
  let(:code) { Pando::Invite.encode(bundle: bundle.to_h, name: "Zoe") }

  it "fits a real invite code into a QR at the lowest error-correction level" do
    # RQRCode raises when the payload exceeds byte-mode capacity.
    qr = RQRCode::QRCode.new(code, level: :l)

    png = qr.as_png(size: 462, border_modules: 2).to_s
    expect(png[1, 3]).to eq("PNG")
  end

  it "round-trips an invite through a file back into a contact card" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "zoe-invite.txt")
      File.write(path, "#{code}\n")

      invite = Pando::Invite.decode(File.read(path, 4096).strip)

      expect(invite.fingerprint).to eq(account.fingerprint)
      expect(invite.name).to eq("Zoe")
    end
  end
end
