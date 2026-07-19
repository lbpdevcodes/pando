# frozen_string_literal: true

require "tmpdir"

# A fake OS adapter with Charming::Audio::System's interface — we wrap the
# process table behind the adapter and fake THAT, never Process itself.
class FakeAudioSystem
  attr_reader :spawned, :terminated

  def initialize(os: :macos, commands: [])
    @os = os
    @commands = commands
    @spawned = []
    @terminated = []
    @next_pid = 100
  end

  def macos? = @os == :macos

  def linux? = @os == :linux

  def which?(command) = @commands.include?(command)

  def spawn(argv)
    @spawned << argv
    @next_pid += 1
  end

  def terminate(pid) = @terminated << pid

  def alive?(pid) = !@terminated.include?(pid)

  def wait(pid) = nil
end

RSpec.describe Pando::Audio::Recorder do
  let(:path) { File.join(Dir.mktmpdir, "note.wav") }

  def recorder(os: :macos, commands: ["rec"])
    described_class.new(system: FakeAudioSystem.new(os: os, commands: commands))
  end

  it "prefers sox's rec with a 16kHz mono wav command line" do
    rec = recorder(commands: %w[rec ffmpeg pw-record])
    rec.start(path)

    argv = rec.system.spawned.sole
    expect(argv).to eq(["rec", "-q", "-r", "16000", "-c", "1", path])
  end

  it "falls back to ffmpeg with the platform capture device" do
    mac = recorder(os: :macos, commands: ["ffmpeg"])
    mac.start(path)
    expect(mac.system.spawned.sole).to include("-f", "avfoundation", "-i", ":default")

    linux = recorder(os: :linux, commands: ["ffmpeg"])
    linux.start(path)
    expect(linux.system.spawned.sole).to include("-f", "pulse", "-i", "default")
  end

  it "uses pw-record on linux when ffmpeg and sox are missing" do
    rec = recorder(os: :linux, commands: ["pw-record"])
    rec.start(path)

    expect(rec.system.spawned.sole.first).to eq("pw-record")
  end

  it "raises Unavailable when no backend exists" do
    expect { recorder(commands: []).start(path) }
      .to raise_error(described_class::Unavailable)
  end

  it "tracks recording state and elapsed time through stop" do
    rec = recorder
    expect(rec.recording?).to be(false)

    rec.start(path)
    expect(rec.recording?).to be(true)
    expect(rec.elapsed).to be >= 0

    rec.stop
    expect(rec.recording?).to be(false)
    expect(rec.system.terminated.length).to eq(1)
  end

  it "is idempotent on stop and refuses double-start" do
    rec = recorder
    rec.stop
    expect(rec.system.terminated).to be_empty

    rec.start(path)
    expect { rec.start(path) }.to raise_error(described_class::AlreadyRecording)
  end

  it "cancel stops the child and deletes the partial file" do
    rec = recorder
    rec.start(path)
    File.write(path, "partial wav")

    rec.cancel

    expect(File.exist?(path)).to be(false)
    expect(rec.system.terminated.length).to eq(1)
    expect(rec.recording?).to be(false)
  end
end
