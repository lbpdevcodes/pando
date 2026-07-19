# frozen_string_literal: true

require "tmpdir"
require "socket"
require "timeout"

RSpec.describe Pando::Client::Hub do
  let(:recorder) do
    Class.new do
      def reports = @reports ||= []

      def report(current, of: nil, message: nil) = reports << message
    end.new
  end

  def free_port
    TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }
  end

  def wait_until(timeout: 5)
    Timeout.timeout(timeout) { sleep 0.02 until yield }
  end

  def build_hub(port)
    described_class.new(identity: Pando::Crypto::Identity.generate, relay_url: "http://127.0.0.1:#{port}")
  end

  context "with a live relay" do
    around do |example|
      Dir.mktmpdir do |dir|
        @db_path = File.join(dir, "relay.db")
        @port = free_port
        app = Pando::Relay::App.new(db_path: @db_path)
        @server = Thread.new { Pando::Relay::App.serve(app, host: "127.0.0.1", port: @port) }
        wait_until do
          TCPSocket.new("127.0.0.1", @port).close
          true
        rescue Errno::ECONNREFUSED
          false
        end
        example.run
      ensure
        @hub&.stop!
        @hub_thread&.join
        @server&.kill
        @server&.join
      end
    end

    def start_hub
      @hub = build_hub(@port)
      @hub_thread = Thread.new { @hub.run(recorder) }
      wait_until { recorder.reports.any? { |r| r && r["value"] == "online" } }
      @hub
    end

    it "publishes its bundle and reports online" do
      hub = start_hub

      published = Pando::Relay::Directory.new(@db_path).bundle_for_mailbox(hub.device.mailbox)
      expect(published).not_to be_nil
      expect(recorder.reports).to include(hash_including("value" => "online"))
    end

    it "pumps enqueued sends out to recipients" do
      hub = start_hub
      peer_account = Pando::Crypto::Account.generate
      peer = Pando::Crypto::Device.generate
      Pando::Relay::Directory.new(@db_path)
        .publish(Pando::Crypto::DeviceBundle.issue(device: peer, account: peer_account).to_h)
      peer_conn = Pando::Client::Connection.open("ws://127.0.0.1:#{@port}/v1/ws", device: peer)

      envelope = Pando::Protocol::Envelope.seal("psst", from: hub.device, to: peer.encryption_public_key)
      hub.send_envelope(id: "m1/#{peer.mailbox}", to: peer.mailbox, envelope: envelope.to_h, ttl: 0)

      frame = peer_conn.next_frame
      expect(frame).to be_a(Pando::Protocol::Frames::Message)
      expect(Pando::Protocol::Envelope.from_h(frame.envelope).open(with: peer)).to eq("psst")
      peer_conn.close
    end

    it "surfaces incoming frames as progress reports" do
      hub = start_hub
      sender = Pando::Crypto::Device.generate
      envelope = Pando::Protocol::Envelope.seal("hello hub", from: sender, to: hub.device.encryption_public_key)

      sender_account = Pando::Crypto::Account.generate
      Pando::Relay::Directory.new(@db_path)
        .publish(Pando::Crypto::DeviceBundle.issue(device: sender, account: sender_account).to_h)
      sender_conn = Pando::Client::Connection.open("ws://127.0.0.1:#{@port}/v1/ws", device: sender)
      sender_conn.send_envelope(id: "x/#{hub.device.mailbox}", to: hub.device.mailbox,
        envelope: envelope.to_h, ttl: 0)

      wait_until { recorder.reports.any? { |r| r && r["type"] == "frame" } }
      frame = recorder.reports.find { |r| r["type"] == "frame" }.fetch("frame")
      expect(frame).to be_a(Pando::Protocol::Frames::Message)
      sender_conn.close
    end
  end

  it "reports reconnecting when no relay is reachable" do
    hub = build_hub(free_port)
    thread = Thread.new { hub.run(recorder) }

    Timeout.timeout(5) { sleep 0.02 until recorder.reports.any? { |r| r && r["value"] == "reconnecting" } }
    hub.stop!
    thread.join

    expect(recorder.reports).to include(hash_including("value" => "reconnecting"))
    expect(recorder.reports.last).to include("value" => "offline")
  end
end
