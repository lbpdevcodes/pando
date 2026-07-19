# frozen_string_literal: true

require "tmpdir"
require "socket"
require "timeout"

# A connected client under test: its Hub, the thread running it, and the reports
# the Hub surfaces (status changes and inbound frames).
LiveClient = Struct.new(:hub, :thread, :reports, :fingerprint, :name) do
  def stop
    hub.stop!
    thread.join
  end

  def invite_code = hub.invite_code(name: name)
end

# Two full clients (Hub + Ingestor, the same pieces the TUI runs) exchange a live
# DM through a real relay process — the Phase 4 end-to-end proof.
RSpec.describe "Live DM between two clients", :integration do
  around do |example|
    Dir.mktmpdir do |dir|
      @db_path = File.join(dir, "relay.db")
      @port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
      app = Pando::Relay::App.new(db_path: @db_path)
      @server = Thread.new { Pando::Relay::App.serve(app, host: "127.0.0.1", port: @port) }
      wait_until { port_open? }
      example.run
    ensure
      @clients&.each(&:stop)
      @server&.kill
      @server&.join
    end
  end

  def relay_url = "http://127.0.0.1:#{@port}"

  def port_open?
    TCPSocket.new("127.0.0.1", @port).close
    true
  rescue Errno::ECONNREFUSED
    false
  end

  def wait_until(timeout: 5)
    Timeout.timeout(timeout) { sleep 0.02 until yield }
  end

  def start_client(name)
    identity = Pando::Crypto::Identity.generate
    hub = Pando::Client::Hub.new(identity: identity, relay_url: relay_url)
    reports = []
    recorder = build_recorder(reports)
    thread = Thread.new { hub.run(recorder) }
    wait_until { reports.any? { |r| r && r["value"] == "online" } }
    client = LiveClient.new(hub: hub, thread: thread, reports: reports,
      fingerprint: Pando::Crypto::Identity.account_from(identity).fingerprint, name: name)
    @clients << client
    client
  end

  def build_recorder(reports)
    Class.new do
      define_method(:initialize) { @reports = reports }
      define_method(:report) { |current, of: nil, message: nil| @reports << message }
    end.new
  end

  before { @clients = [] }

  it "delivers a typed message and drives its status to delivered" do
    alice = start_client("Alice")
    bob = start_client("Bob")

    # Each side adds the other from an invite code, exactly as the TUI does.
    alice_ingestor = ingestor_for(alice)
    bob_ingestor = ingestor_for(bob)
    add_contact(on: alice, invite: bob.invite_code)
    add_contact(on: bob, invite: alice.invite_code)

    conversation = Pando::Conversation.find_by(key: dm_key(alice, bob))
    send_text(alice, conversation, "hey bob, this is live")

    # Bob's client ingests the inbound frame → an incoming message row.
    wait_until { pump(bob, bob_ingestor) { Pando::Message.where(direction: "incoming").exists? } }
    incoming = Pando::Message.where(direction: "incoming").last
    expect(incoming.body).to eq("hey bob, this is live")

    # Bob's delivered receipt flows back → Alice's outgoing goes delivered.
    outgoing = Pando::Message.where(direction: "outgoing").last
    wait_until { pump(alice, alice_ingestor) { outgoing.reload.status == "delivered" } }
    expect(outgoing.status).to eq("delivered")
  end

  def ingestor_for(client)
    Pando::Ingestor.new(hub: client.hub)
  end

  def add_contact(on:, invite:)
    Pando::AddContact.new(my_fingerprint: on.fingerprint)
      .call(Pando::Invite.decode(invite))
  end

  def dm_key(a, b)
    Pando::Protocol::Content.dm_conversation(a.fingerprint, b.fingerprint)
  end

  def send_text(client, conversation, body)
    message = conversation.messages.create!(direction: "outgoing", body: body, status: "pending",
      sent_at: Time.now.utc, content_id: SecureRandom.uuid)
    bundles = conversation.contacts.filter_map(&:device_bundle)
    content = Pando::Protocol::Content.new(kind: "text", conversation: conversation.key,
      body: body, id: message.content_id)
    Pando::Client::Outbox.new(connection: client.hub, device: client.hub.device)
      .deliver(content, to_bundles: bundles)
  end

  # Ingests every frame the client's Hub has surfaced so far, then yields the stop
  # condition. Re-ingesting is safe — content ids dedupe — so we never risk racing
  # the Hub thread by mutating its report list.
  def pump(client, ingestor)
    client.reports.dup.each do |report|
      ingestor.ingest_frame(report["frame"]) if report && report["type"] == "frame"
    end
    yield
  end
end
