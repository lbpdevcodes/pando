# frozen_string_literal: true

module Pando
  class ApplicationController < Charming::Controller
    include Charming::Shell::Sidebar
    include Charming::Shell::Palette
    include Connectivity
    include Sweeping

    layout Layouts::ApplicationLayout
    focus_ring :sidebar, :content

    # `?` is global, but the key ladder hands printables to a focused text
    # component first — typing "?" into the composer still inserts a "?".
    key "?", :open_help, scope: :global
    key "ctrl+p", :open_command_palette, scope: :global
    key "q", :quit, scope: :global

    timer :toast_expiry, every: 0.5, action: :expire_toast
    timer :typing_expiry, every: 2, action: :expire_typing

    command "Help", :open_help

    command "Home" do
      navigate :root
    end

    command "Theme", :open_theme_palette
    command "Close palette", :close_command_palette
    command "Quit app", :quit

    # Focus slot: the shortcut cheat-sheet (content is derived from the
    # controller class, so it never changes mid-screen).
    slot(:help_overlay) { Charming::Components::HelpOverlay.for_controller(self.class, theme: theme) }
    on_cancel :help_overlay, :help_overlay_cancelled

    # Opens the keyboard-shortcut overlay; any key dismisses it.
    def open_help
      dismiss_command_palette
      return render_default_action if session[:help_open]

      session[:help_open] = true
      focus.push_scope([:help_overlay], origin: :modal)
      render_default_action
    end

    def help_overlay_cancelled
      session.delete(:help_open)
      focus.pop_scope
      render_default_action
    end

    # Timer action: drops stale typing hints; repaints only when one expired.
    def expire_typing
      typing = session[:typing]
      return if typing.nil? || typing.empty?

      stale = typing.select { |_key, stamp| Time.now.to_f - stamp >= 6 }
      return if stale.empty?

      stale.each_key { |key| typing.delete(key) }
      render_default_action
    end

    # Shows an auto-dismissing toast (rendered by the layout as an overlay).
    def show_toast(message, kind: :success)
      session[:toast] = {message: message, kind: kind, expires_at: Time.now.to_f + 2.5}
    end

    # Closes the palette without assigning a response. Charming's
    # close_command_palette renders, so calling it inside an action that also
    # renders raises DoubleRenderError — and the modal would paint under the
    # still-open palette. Safe no-op when the palette is closed.
    def dismiss_command_palette
      session.delete(:command_palette)
      focus.pop_scope while focus.ring == [:command_palette]
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
