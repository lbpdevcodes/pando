# frozen_string_literal: true

module Pando
  class ApplicationController < Charming::Controller
    include Connectivity
    include Sweeping

    layout Layouts::ApplicationLayout
    focus_ring :sidebar, :content

    key "ctrl+p", :open_command_palette, scope: :global
    key "q", :quit, scope: :global

    timer :toast_expiry, every: 0.5, action: :expire_toast

    command "Home" do
      navigate_to "/"
    end

    command "Theme", :open_theme_palette
    command "Close palette", :close_command_palette
    command "Quit app", :quit

    # Shows an auto-dismissing toast (rendered by the layout as an overlay).
    def show_toast(message, kind: :success)
      session[:toast] = {message: message, kind: kind, expires_at: Time.now.to_f + 2.5}
    end

    # Timer action: clears the toast once its deadline passes. Renders only when
    # something actually changed.
    def expire_toast
      toast = session[:toast]
      return unless toast
      return if Time.now.to_f < toast[:expires_at]

      session.delete(:toast)
      render_default_action
    end

    # Quit must reap audio children: the recorder/player processes outlive the
    # task threads the runtime hard-kills shortly after shutdown.
    def quit
      session[:recorder]&.cancel
      session[:audio_player]&.stop
      super
    end
  end
end
