# frozen_string_literal: true

require "rqrcode"

module Pando
  # QrInviteUi renders the user's invite code as an inline Kitty QR (with a
  # text fallback) and accepts an invite from a file — SPEC treats text and QR
  # as equivalent carriers, and no maintained pure-Ruby QR *image* decoder
  # exists (zxing needs the JVM, zxing-cpp a native lib), so the input side
  # reads the code as text. A future option: shell out to zbarimg when
  # installed.
  module QrInviteUi
    def self.included(base)
      base.command "Show my invite QR", :open_invite_qr
      base.command "Load invite from file", :open_invite_file_picker

      base.slot(:invite_qr_card) { QrInviteCard.new(source: nil, code: nil, theme: theme) }
      base.slot(:invite_file_picker) { AttachPicker.new(root: attach_root, height: 12, theme: theme) }

      base.on_cancel :invite_qr_card, :invite_qr_card_cancelled
      base.on_select :invite_file_picker, :invite_file_picker_selected
      base.on_cancel :invite_file_picker, :invite_file_picker_cancelled
    end

    def open_invite_qr
      dismiss_command_palette
      session[:invite_qr_open] = true
      build_qr_source
      invite_qr_card.configure(source: session[:qr_source], code: my_invite_code)
      focus.push_scope([:invite_qr_card], origin: :modal)
      show
    end

    def invite_qr_card_cancelled
      close_invite_qr
      show
    end

    def open_invite_file_picker
      dismiss_command_palette
      session[:invite_file_open] = true
      focus.push_scope([:invite_file_picker], origin: :modal)
      show
    end

    def invite_file_picker_selected(path)
      close_invite_file_picker
      invite = Invite.decode(File.read(path, 4096).to_s.strip)
      AddContactFromInvite.new(my_fingerprint: my_fingerprint, my_name: my_display_name,
        hub: hub).call(invite)
      reload_conversations
      show_toast(add_contact_toast(invite))
      show
    rescue Invite::Malformed
      show_toast("That file isn't an invite", kind: :warn)
      show
    end

    def invite_file_picker_cancelled
      close_invite_file_picker
      show
    end

    private

    # Built from the sealed identity, so it works offline too.
    def my_invite_code
      identity = session[:identity]
      account = Crypto::Identity.account_from(identity)
      device = Crypto::Identity.device_from(identity)
      Invite.encode(bundle: Crypto::DeviceBundle.issue(device: device, account: account).to_h,
        name: my_display_name)
    end

    # A dedicated source (NOT the transcript cache, whose retain pass would
    # release it mid-display); freed explicitly on close.
    def build_qr_source
      return unless Graphics.supports?

      png = RQRCode::QRCode.new(my_invite_code, level: :l).as_png(size: 462, border_modules: 2).to_s
      session[:qr_source] = Charming::Image::Source.new(data: png, terminal: Graphics.terminal)
    end

    def close_invite_qr
      session[:invite_qr_open] = false
      if (source = session.delete(:qr_source))
        Charming::Escape.register(source.release)
      end
      focus.pop_scope
    end

    # The picker is memoized for the screen's lifetime, so it reopens where the
    # user left off — no directory write-back needed.
    def close_invite_file_picker
      session[:invite_file_open] = false
      focus.pop_scope
    end

    def qr_invite_modal
      if session[:invite_qr_open]
        {title: "My invite QR", content: invite_qr_card, help: "any key closes"}
      elsif session[:invite_file_open]
        {title: "Load invite from file", content: invite_file_picker,
         help: "enter open/select · backspace up · esc cancel"}
      end
    end
  end
end
