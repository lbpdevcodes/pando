# frozen_string_literal: true

require "tmpdir"

RSpec.describe Pando::Relay::QueueStore do
  around do |example|
    Dir.mktmpdir { |dir| @db_path = File.join(dir, "relay.db") and example.run }
  end

  let(:limits) { Pando::Protocol::Limits.new(max_queued_messages: 3, max_queued_bytes: 200, max_frame_bytes: 1024, queue_ttl: 60) }
  let(:store) { described_class.new(@db_path, limits: limits) }
  let(:now) { Time.now.to_i }

  def enqueue(mailbox: "m1", envelope: '{"c":"x"}', expires_at: now + 60)
    store.enqueue(mailbox: mailbox, envelope: envelope, expires_at: expires_at)
  end

  it "drains queued envelopes in order without deleting them" do
    enqueue(envelope: '{"c":"first"}')
    enqueue(envelope: '{"c":"second"}')

    drained = store.drain(mailbox: "m1", now: now)

    expect(drained.map { |m| m.fetch(:envelope) }).to eq(['{"c":"first"}', '{"c":"second"}'])
    expect(store.drain(mailbox: "m1", now: now).length).to eq(2)
  end

  it "drains only the requested mailbox" do
    enqueue(mailbox: "m1")
    enqueue(mailbox: "m2")

    expect(store.drain(mailbox: "m2", now: now).length).to eq(1)
  end

  it "excludes expired envelopes from drains" do
    enqueue(expires_at: now - 1)
    enqueue(expires_at: now + 60)

    expect(store.drain(mailbox: "m1", now: now).length).to eq(1)
  end

  it "deletes an envelope on ack" do
    seq = enqueue

    store.ack(seq: seq)

    expect(store.drain(mailbox: "m1", now: now)).to be_empty
  end

  it "refuses to queue past the message-count cap" do
    3.times { enqueue }

    expect { enqueue }.to raise_error(described_class::QueueFull)
  end

  it "refuses to queue past the byte cap" do
    enqueue(envelope: "x" * 150)

    expect { enqueue(envelope: "y" * 100) }.to raise_error(described_class::QueueFull)
  end

  it "sweeps expired envelopes" do
    enqueue(expires_at: now - 1)
    enqueue(expires_at: now + 60)

    expect(store.sweep(now: now)).to eq(1)
  end

  it "keeps its queue across reopens" do
    enqueue(envelope: '{"c":"durable"}')

    reopened = described_class.new(@db_path, limits: limits)

    expect(reopened.drain(mailbox: "m1", now: now).first.fetch(:envelope)).to eq('{"c":"durable"}')
  end
end
