# frozen_string_literal: true

require "tmpdir"
require "socket"
require "timeout"

# The relay's periodic sweep must PURGE expired queued rows, not just hide
# them: drain already filters by expires_at, so the stored row count is the
# load-bearing assertion.
RSpec.describe "Relay queue sweep timer", :integration do
  around do |example|
    Dir.mktmpdir do |dir|
      @db_path = File.join(dir, "relay.db")
      @port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
      app = Pando::Relay::App.new(db_path: @db_path)
      @server = Thread.new do
        Pando::Relay::App.serve(app, host: "127.0.0.1", port: @port, sweep_interval: 0.2)
      end
      Timeout.timeout(5) do
        TCPSocket.new("127.0.0.1", @port).close
      rescue Errno::ECONNREFUSED
        sleep 0.05
        retry
      end
      example.run
    ensure
      @server&.kill
      @server&.join
    end
  end

  it "purges expired queued messages without anyone draining them" do
    sender = Pando::Crypto::Device.generate
    offline_account = Pando::Crypto::Account.generate
    offline = Pando::Crypto::Device.generate
    directory = Pando::Relay::Directory.new(@db_path)
    directory.publish(Pando::Crypto::DeviceBundle.issue(device: sender,
      account: Pando::Crypto::Account.generate).to_h)
    directory.publish(Pando::Crypto::DeviceBundle.issue(device: offline,
      account: offline_account).to_h)

    connection = Pando::Client::Connection.open("ws://127.0.0.1:#{@port}/v1/ws", device: sender)
    envelope = Pando::Protocol::Envelope.seal("ephemeral", from: sender,
      to: offline.encryption_public_key)
    connection.send_envelope(id: "e1/#{offline.mailbox}", to: offline.mailbox,
      envelope: envelope.to_h, ttl: 1)
    receipt = connection.next_frame
    expect(receipt.status).to eq("queued")

    queue = Pando::Relay::QueueStore.new(@db_path)
    expect(queue.drain(mailbox: offline.mailbox, now: Time.now.to_i).length).to eq(1)

    # Past expiry + at least one sweep tick: the ROW is gone from the store.
    Timeout.timeout(5) do
      sleep 0.2 while queue.drain(mailbox: offline.mailbox, now: Time.now.to_i - 10).any?
    end
    connection.close
  end
end
