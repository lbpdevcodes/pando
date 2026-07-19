# frozen_string_literal: true

require_relative "../support/live_relay_harness"
require "pty"
require "io/console"

# The real app in a real PTY — the one place background-event rendering is
# observable. Charming paints timers silently (nil response = skip) but task
# and task-progress dispatches fall back to render(""), so a background
# handler that returns nil wipes the screen — including any open modal —
# every time it fires. This spec pins the whole-app invariant the journey
# suite (inline executor, no background events) cannot see:
#
#   an idle, connected pando paints NOTHING, and an open palette stays open.
RSpec.describe "Live TUI idle stability", :integration do
  include LiveRelayHarness

  let(:child_env_name) { "tui_probe" }

  def child_db = File.expand_path("../../db/#{child_env_name}.sqlite3", __dir__)

  around do |example|
    Dir.mktmpdir do |dir|
      @pando_root = dir
      FileUtils.rm_f(child_db)
      system({"CHARMING_ENV" => child_env_name}, "bundle", "exec", "charming", "db:setup",
        out: File::NULL, err: File::NULL) || raise("db:setup failed for #{child_env_name}")
      example.run
    ensure
      FileUtils.rm_f(child_db)
    end
  end

  def drain(reader, seconds)
    deadline = Time.now + seconds
    while Time.now < deadline
      next unless IO.select([reader], nil, nil, 0.1)

      begin
        reader.read_nonblock(65_536)
      rescue IO::WaitReadable, Errno::EIO
        nil
      end
    end
  end

  def paints(log_path)
    File.exist?(log_path) ? File.readlines(log_path) : []
  end

  # The child freezes if its PTY output isn't consumed, so waiting must keep
  # draining — a sleeping wait_until would deadlock the app under test.
  def drain_until(reader, message:, timeout: 10)
    deadline = Time.now + timeout
    loop do
      drain(reader, 0.2)
      return if yield
      raise "#{message} within #{timeout}s" if Time.now > deadline
    end
  end

  it "does not repaint while idle and keeps the palette open" do
    log_path = File.join(@pando_root, "frames.log")
    env = {
      "PANDO_ROOT" => @pando_root, "CHARMING_ENV" => child_env_name,
      "PANDO_RELAY" => relay_url, "FRAME_LOG" => log_path,
      "TERM" => "xterm-256color"
    }
    launcher = File.expand_path("../support/tui_probe_launcher.rb", __dir__)

    PTY.spawn(env, "bundle", "exec", "ruby", launcher) do |reader, writer, pid|
      reader.winsize = [30, 100]
      drain(reader, 3) # boot into onboarding
      writer.write("probepass123\r") # create profile + unlock
      drain_until(reader, message: "never reached online") do
        paints(log_path).any? { |l| l.include?("online") }
      end
      drain(reader, 1.5) # settle

      # Idle: nothing may paint.
      idle_start = paints(log_path).length
      drain(reader, 3)
      idle_paints = paints(log_path)[idle_start..]
      expect(idle_paints).to be_empty,
        "expected no repaints while idle, got:\n#{idle_paints.join}"

      # Palette: opening paints once, then nothing may wipe it.
      writer.write("\x10") # ctrl+p
      drain_until(reader, message: "palette never opened") do
        paints(log_path).last.to_s.include?("Close palette")
      end
      palette_start = paints(log_path).length
      drain(reader, 2.5)
      after_palette = paints(log_path)[palette_start..]
      expect(after_palette).to be_empty,
        "expected the open palette to survive, got:\n#{after_palette.join}"
    ensure
      writer.write("\x03")
      sleep 0.2
      begin
        Process.kill("KILL", pid)
      rescue Errno::ESRCH
        nil
      end
    end
  end
end
