# frozen_string_literal: true

require "fileutils"

module Pando
  # AttachmentsUi is the chat screen's file surface: a Filepicker modal to
  # attach, save-on-explicit-action for received files, and the per-session
  # graphics cache that renders complete PNG attachments inline (newest few
  # only — the cache cap plus release-on-eviction keeps terminal memory
  # bounded no matter how image-heavy the transcript gets).
  module AttachmentsUi
    def self.included(base)
      base.command "Attach file", :open_attach_picker
      base.command "Save attachment", :save_latest_attachment

      base.slot(:attach_picker) { AttachPicker.new(root: attach_root, height: 12, theme: theme) }

      base.on_select :attach_picker, :attach_picker_selected
      base.on_cancel :attach_picker, :attach_picker_cancelled
    end

    def open_attach_picker
      dismiss_command_palette
      return no_conversation_for_attach unless active_conversation

      session[:attach_open] = true
      focus.push_scope([:attach_picker], origin: :modal)
      show
    end

    def attach_picker_selected(path)
      conversation = active_conversation
      close_attach_picker
      message = Attachments::Sender.new(hub: hub).call(path: path, conversation: conversation)
      show_toast(hub ? "Sending #{message.body}" : "Attached #{message.body} (offline — will not send)",
        kind: hub ? :success : :warn)
      chat_state.follow = true
      show
    rescue Attachments::Sender::TooLarge
      show_toast("File is over the #{Attachments::MAX_ATTACHMENT_BYTES / (1024 * 1024)} MB attachment limit", kind: :warn)
      show
    end

    def attach_picker_cancelled
      close_attach_picker
      show
    end

    def save_latest_attachment
      dismiss_command_palette
      attachment = latest_complete_attachment
      return no_attachment_to_save unless attachment

      path = write_download(attachment)
      show_toast("Saved to #{path}")
      show
    end

    private

    def no_conversation_for_attach
      show_toast("Open a conversation first", kind: :warn)
      show
    end

    def no_attachment_to_save
      show_toast("No completed attachment in this conversation", kind: :warn)
      show
    end

    def latest_complete_attachment
      return nil unless active_conversation

      Attachment.where(message: active_conversation.messages, status: "complete")
        .order(:id).last
    end

    def write_download(attachment)
      dir = ENV["PANDO_DOWNLOADS"] || File.join(Dir.home, "Downloads")
      FileUtils.mkdir_p(dir)
      path = collision_free_path(dir, attachment.name)
      File.binwrite(path, Attachments::BlobStore.new.read(attachment.attachment_id))
      File.chmod(0o600, path)
      path
    end

    def collision_free_path(dir, name)
      candidate = File.join(dir, name)
      return candidate unless File.exist?(candidate)

      ext = File.extname(name)
      base = File.basename(name, ext)
      (1..).each do |n|
        candidate = File.join(dir, "#{base} (#{n})#{ext}")
        return candidate unless File.exist?(candidate)
      end
    end

    def attach_root
      ENV["PANDO_ATTACH_ROOT"] || Dir.home
    end

    def attachments_modal
      return nil unless session[:attach_open]

      {title: "Attach file", content: attach_picker,
       help: "enter open/select · backspace up · esc cancel"}
    end

    # The picker is memoized for the screen's lifetime, so it reopens where the
    # user left off — no directory write-back needed.
    def close_attach_picker
      session[:attach_open] = false
      focus.pop_scope
    end

    # Placement blocks for the newest complete PNG attachments; everything
    # else in the cache is released. Built during dispatch so the escape
    # collector picks up transmits and deletes.
    def transcript_image_blocks(messages)
      return {} unless Graphics.supports?

      cache = (session[:graphics_cache] ||= Graphics::Cache.new)
      renderable = messages.select { |m| renderable_image?(m) }.last(Graphics::MAX_SOURCES)
      cache.retain(renderable.map { |m| m.attachment.attachment_id })
      renderable.each_with_object({}) do |message, blocks|
        lines = placement_lines(cache, message.attachment)
        blocks[message.id] = lines if lines
      end
    end

    def renderable_image?(message)
      message.kind == "attachment" && message.attachment&.status == "complete" &&
        message.attachment.png?
    end

    def placement_lines(cache, attachment)
      entry = cache.fetch(attachment.attachment_id, max_cols: transcript_width - 6) do
        Attachments::BlobStore.new.read(attachment.attachment_id)
      end
      return nil unless entry

      Charming::Components::Image.new(source: entry[:source], rows: entry[:rows],
        cols: entry[:cols]).render.split("\n")
    end
  end
end
