# frozen_string_literal: true

RSpec.describe Pando::Client::Backoff do
  it "grows delays exponentially up to the cap" do
    backoff = described_class.new(base: 1, cap: 8, jitter: ->(delay) { delay })

    expect(4.times.map { backoff.next_delay }).to eq([1, 2, 4, 8])
    expect(backoff.next_delay).to eq(8)
  end

  it "restarts from the base after a reset" do
    backoff = described_class.new(base: 1, cap: 8, jitter: ->(delay) { delay })
    3.times { backoff.next_delay }

    backoff.reset

    expect(backoff.next_delay).to eq(1)
  end

  it "jitters delays downward only" do
    backoff = described_class.new(base: 4, cap: 60)

    delays = 20.times.map { backoff.reset && backoff.next_delay }
    expect(delays).to all(be_between(2, 4))
  end
end
