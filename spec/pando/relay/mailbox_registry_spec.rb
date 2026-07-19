# frozen_string_literal: true

RSpec.describe Pando::Relay::MailboxRegistry do
  let(:registry) { described_class.new }
  let(:session) { Object.new }

  it "finds live sessions for a mailbox" do
    registry.register("m1", session)

    expect(registry.sessions_for("m1")).to eq([session])
    expect(registry.sessions_for("m2")).to be_empty
  end

  it "forgets unregistered sessions" do
    registry.register("m1", session)
    registry.unregister("m1", session)

    expect(registry.sessions_for("m1")).to be_empty
  end

  it "supports multiple sessions per mailbox" do
    other = Object.new
    registry.register("m1", session)
    registry.register("m1", other)

    expect(registry.sessions_for("m1")).to contain_exactly(session, other)
  end
end
