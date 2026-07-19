# frozen_string_literal: true

require "tmpdir"
require "socket"
require "timeout"
require "securerandom"

# A connected client under test: its Hub, the thread running it, and the reports
# the Hub surfaces (status changes and inbound frames).
LiveClient = Struct.new(:hub, :thread, :reports, :fingerprint, :name) do
  def stop
    hub.stop!
    thread.join
  end

  def invite_code = hub.invite_code(name: name)
end

# LiveRelayHarness boots a real in-thread relay around each example and spins up
# full clients (Hub on its own thread + Ingestor — the same pieces the TUI runs).
# Override #relay_app_options in a spec to boot the relay with a token or custom
# limits; pass hub options (discoverable:, token:) through #start_client.
module LiveRelayHarness
  def self.included(spec)
    spec.around do |example|
      Dir.mktmpdir do |dir|
        @db_path = File.join(dir, "relay.db")
        @port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
        app = Pando::Relay::App.new(db_path: @db_path, **relay_app_options)
        @server = Thread.new { Pando::Relay::App.serve(app, host: "127.0.0.1", port: @port) }
        wait_until { port_open? }
        example.run
      ensure
        @clients&.each(&:stop)
        @server&.kill
        @server&.join
      end
    end

    spec.before { @clients = [] }
  end

  def relay_app_options = {}

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

  def start_client(name, **hub_options)
    identity = Pando::Crypto::Identity.generate
    hub = Pando::Client::Hub.new(identity: identity, relay_url: relay_url, **hub_options)
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
    message
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
