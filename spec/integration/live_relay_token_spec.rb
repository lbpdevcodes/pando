# frozen_string_literal: true

require_relative "../support/live_relay_harness"

# A token-gated relay: both the HTTP directory surface and the WebSocket
# upgrade require the X-Pando-Relay-Token header, so a Hub configured with the
# token reaches online while one without it never gets past the door.
RSpec.describe "Live token-gated relay", :integration do
  include LiveRelayHarness

  def relay_app_options = {token: "sekrit"}

  it "connects a hub that presents the relay token" do
    client = start_client("Alice", token: "sekrit")

    expect(client.reports).to include(hash_including("value" => "online"))
  end

  it "keeps a tokenless hub stuck reconnecting" do
    identity = Pando::Crypto::Identity.generate
    hub = Pando::Client::Hub.new(identity: identity, relay_url: relay_url)
    reports = []
    thread = Thread.new { hub.run(build_recorder(reports)) }

    wait_until { reports.any? { |r| r && r["value"] == "reconnecting" } }
    hub.stop!
    thread.join

    expect(reports).not_to include(hash_including("value" => "online"))
  end
end
