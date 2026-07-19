# frozen_string_literal: true

require "tmpdir"
require "socket"

RSpec.describe "Relay round-trip", :integration do
  around do |example|
    Dir.mktmpdir do |dir|
      @db_path = File.join(dir, "relay.db")
      @port = free_port
      @server = start_relay
      example.run
    ensure
      @server&.kill
      @server&.join
    end
  end

  def free_port
    TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }
  end

  def limits
    Pando::Protocol::Limits.new(max_queued_messages: 2, max_queued_bytes: 4096, max_frame_bytes: 2048, queue_ttl: 60)
  end

  def start_relay
    app = Pando::Relay::App.new(db_path: @db_path, limits: limits)
    thread = Thread.new { Pando::Relay::App.serve(app, host: "127.0.0.1", port: @port) }
    wait_for_port
    thread
  end

  def wait_for_port
    50.times do
      TCPSocket.new("127.0.0.1", @port).close
      return
    rescue Errno::ECONNREFUSED
      sleep 0.05
    end
    raise "relay never came up on port #{@port}"
  end

  def ws_url = "ws://127.0.0.1:#{@port}/v1/ws"

  def enrolled_peer
    account = Pando::Crypto::Account.generate
    device = Pando::Crypto::Device.generate
    bundle = Pando::Crypto::DeviceBundle.issue(device: device, account: account)
    Pando::Relay::Directory.new(@db_path).publish(bundle.to_h)
    [device, bundle]
  end

  def sent_content(body = "hello over the wire")
    Pando::Protocol::Content.text(body, conversation: "dm:a:b")
  end

  it "delivers live between two connected clients and reports delivered" do
    alice, _alice_bundle = enrolled_peer
    bob, bob_bundle = enrolled_peer

    alice_conn = Pando::Client::Connection.open(ws_url, device: alice)
    bob_conn = Pando::Client::Connection.open(ws_url, device: bob)

    Pando::Client::Outbox.new(connection: alice_conn, device: alice)
      .deliver(sent_content, to_bundles: [bob_bundle])

    receipt = alice_conn.next_frame
    expect(receipt).to be_a(Pando::Protocol::Frames::Receipt)
    expect(receipt.status).to eq("delivered")

    message = bob_conn.next_frame
    received = Pando::Client::Inbox.new(connection: bob_conn, device: bob).receive(message)
    expect(received.content.body).to eq("hello over the wire")
  ensure
    alice_conn&.close
    bob_conn&.close
  end

  it "queues for offline recipients and drains on subscribe" do
    alice, _ = enrolled_peer
    bob, bob_bundle = enrolled_peer

    alice_conn = Pando::Client::Connection.open(ws_url, device: alice)
    Pando::Client::Outbox.new(connection: alice_conn, device: alice)
      .deliver(sent_content("queued while away"), to_bundles: [bob_bundle])

    expect(alice_conn.next_frame.status).to eq("queued")

    bob_conn = Pando::Client::Connection.open(ws_url, device: bob)
    expect(bob_conn.subscribed.queued).to eq(1)

    received = Pando::Client::Inbox.new(connection: bob_conn, device: bob).receive(bob_conn.next_frame)
    expect(received.content.body).to eq("queued while away")

    # Acked on receive: a reconnect must not replay it.
    bob_conn.close
    reconnected = Pando::Client::Connection.open(ws_url, device: bob)
    expect(reconnected.subscribed.queued).to eq(0)
    reconnected.close
  ensure
    alice_conn&.close
  end

  it "rejects subscribing to a mailbox that was never published" do
    stranger = Pando::Crypto::Device.generate

    expect { Pando::Client::Connection.open(ws_url, device: stranger) }
      .to raise_error(Pando::Client::Connection::SubscribeRejected, /unauthorized/)
  end

  it "rejects subscribing with another device's mailbox" do
    victim, _ = enrolled_peer
    Pando::Crypto::Device.generate
    hijack = Pando::Crypto::Device.new(
      signing_key: RbNaCl::SigningKey.generate,
      encryption_key: RbNaCl::PrivateKey.generate,
      mailbox: victim.mailbox
    )

    expect { Pando::Client::Connection.open(ws_url, device: hijack) }
      .to raise_error(Pando::Client::Connection::SubscribeRejected)
  end

  it "reports queue_full when a mailbox exceeds its cap" do
    alice, _ = enrolled_peer
    _bob, bob_bundle = enrolled_peer

    alice_conn = Pando::Client::Connection.open(ws_url, device: alice)
    outbox = Pando::Client::Outbox.new(connection: alice_conn, device: alice)

    3.times { outbox.deliver(sent_content, to_bundles: [bob_bundle]) }

    statuses = 2.times.map { alice_conn.next_frame }
    error = alice_conn.next_frame
    expect(statuses.map(&:status)).to all(eq("queued"))
    expect(error).to be_a(Pando::Protocol::Frames::Error)
    expect(error.code).to eq("queue_full")
  ensure
    alice_conn&.close
  end

  it "rejects oversized frames" do
    alice, _ = enrolled_peer
    _bob, bob_bundle = enrolled_peer

    alice_conn = Pando::Client::Connection.open(ws_url, device: alice)
    Pando::Client::Outbox.new(connection: alice_conn, device: alice)
      .deliver(sent_content("x" * 4096), to_bundles: [bob_bundle])

    error = alice_conn.next_frame
    expect(error).to be_a(Pando::Protocol::Frames::Error)
    expect(error.code).to eq("frame_too_large")
  ensure
    alice_conn&.close
  end
end
