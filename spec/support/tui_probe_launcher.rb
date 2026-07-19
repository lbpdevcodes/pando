# frozen_string_literal: true

# Boots the real pando app with a frame logger for the PTY smoke spec: every
# Runtime#render appends one line to FRAME_LOG, so the spec can assert exactly
# when the app repaints. Run only as a child process of live_tui_spec.
require "pando"

FRAME_LOG = File.open(ENV.fetch("FRAME_LOG"), "a")
FRAME_LOG.sync = true

module FrameLogger
  def render(response)
    body = response.respond_to?(:body) ? response.body.to_s : response.to_s
    plain = body.gsub(/\e\[[0-9;?]*[a-zA-Z]/, "").gsub(/[│╭╮╰╯─]/, "").gsub(/\s+/, " ").strip
    FRAME_LOG.puts "#{Time.now.strftime("%H:%M:%S.%L")} len=#{plain.length} #{plain[0, 200]}"
    super
  end
end

Charming::Runtime.prepend(FrameLogger)
Charming.run(Pando::Application.new)
