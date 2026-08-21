# frozen_string_literal: true

require "fileutils"
require "securerandom"

module Pando
  # VoiceNotesUi records from the composer (ctrl+r toggles: start, then stop &
  # send as a voice attachment; escape cancels) and plays received notes
  # through the system player. The capture child is spawned directly — never
  # inside a task thread, whose hard-kill on quit would orphan it — and both
  # recorder and player are reaped by the quit override.
  module VoiceNotesUi
    def self.included(base)
      base.key "ctrl+r", :toggle_recording, scope: :global
      base.key "escape", :cancel_recording
      base.command "Record voice note", :toggle_recording
      base.command "Play voice note", :play_latest_voice
      base.key "ctrl+o", :play_latest_voice, scope: :global
      base.timer :recording_tick, every: 1, action: :recording_tick
      base.on_task :playback, action: :playback_finished
    end

    def toggle_recording
      dismiss_command_palette
      return finish_recording if recording?
      return no_conversation_for_voice unless active_conversation

      start_recording
    end

    def cancel_recording
      return render_default_action unless recording?

      recorder.cancel
      session.delete(:recorder)
      show_toast("Recording discarded", kind: :info)
      show
    end

    # Repaints the elapsed counter while recording; silent tick otherwise.
    def recording_tick
      return unless recording?
      return finish_recording if recorder.elapsed >= Pando::Audio::Recorder::MAX_SECONDS

      show
    end

    def play_latest_voice
      dismiss_command_palette
      attachment = latest_voice_attachment
      return no_voice_to_play unless attachment

      start_playback(attachment)
      show_toast("Playing voice note (#{format_duration(attachment.duration_s)})", kind: :info)
      show
    rescue Charming::Audio::Player::Unavailable
      show_toast("No audio player found — install ffmpeg", kind: :warn)
      show
    end

    def playback_finished
      File.delete(session.delete(:playback_path)) if session[:playback_path]
      render_default_action
    rescue Errno::ENOENT
      render_default_action
    end

    private

    def start_recording
      recorder = Pando::Audio.build_recorder
      recorder.start(voice_note_path)
      session[:recorder] = recorder
      show_toast("Recording — ctrl+r to send, esc to discard", kind: :info)
      show
    rescue Pando::Audio::Recorder::Unavailable
      show_toast("No recorder found — install sox or ffmpeg", kind: :warn)
      show
    end

    def finish_recording
      duration = recorder.elapsed
      path = recorder.path
      recorder.stop
      session.delete(:recorder)
      send_voice_note(path, duration)
      show
    end

    def send_voice_note(path, duration)
      message = Attachments::Sender.new(hub: hub)
        .call(path: path, conversation: active_conversation, voice: true, duration_s: duration)
      show_toast("Voice note sent (#{format_duration(duration)})")
      chat_state.follow = true
      message
    ensure
      FileUtils.rm_f(path)
    end

    def start_playback(attachment)
      path = File.join(tmp_dir, "play-#{SecureRandom.hex(6)}.wav")
      File.binwrite(path, Attachments::BlobStore.new.read(attachment.attachment_id))
      File.chmod(0o600, path)
      session[:playback_path] = path
      player = (session[:audio_player] ||= Charming::Audio::Player.new)
      run_task(:playback) do
        player.play(path)
        player.wait
      ensure
        player.stop
      end
    end

    def latest_voice_attachment
      return nil unless active_conversation

      Attachment.where(message: active_conversation.messages, status: "complete", voice: true)
        .order(:id).last
    end

    def recording?
      !!session[:recorder]&.recording?
    end

    def recorder
      session[:recorder]
    end

    def recording_elapsed
      recording? ? recorder.elapsed : nil
    end

    def no_conversation_for_voice
      show_toast("Open a conversation first", kind: :warn)
      show
    end

    def no_voice_to_play
      show_toast("No voice note in this conversation", kind: :warn)
      show
    end

    def voice_note_path
      File.join(tmp_dir, "rec-#{Time.now.utc.strftime("%Y%m%d-%H%M%S")}.wav")
    end

    # Plaintext audio exists only here, only while recording or playing.
    def tmp_dir
      dir = File.join(Store.root, "tmp")
      FileUtils.mkdir_p(dir, mode: 0o700)
      dir
    end

    def format_duration(seconds)
      total = seconds.to_i
      format("%d:%02d", total / 60, total % 60)
    end
  end
end
