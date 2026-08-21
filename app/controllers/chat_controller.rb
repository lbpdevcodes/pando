# frozen_string_literal: true

require "securerandom"

module Pando
  class ChatController < ApplicationController
    include ContactRequestsUi
    include VerificationUi
    include RoomsUi
    include RelaysUi
    include AttachmentsUi
    include VoiceNotesUi
    include EnrollmentUi
    include QrInviteUi

    focus_ring :sidebar, :composer

    key "page_up", :scroll_page_up, scope: :global
    key "page_down", :scroll_page_down, scope: :global
    key "end", :scroll_to_bottom, scope: :global
    # TextArea with enter_newline: false reserves plain Enter for its host —
    # this content-scoped binding is the send action (sidebar Enter still selects).
    key "enter", :send_message

    command "Add contact", :open_add_contact
    command "Copy my invite code", :show_my_invite
    command "Retry failed messages", :retry_failed
    command "Message timer", :cycle_message_ttl

    # The controller outlives one dispatch now, so data memos must be expired
    # per action: inbound frames and timer sweeps mutate rows between renders.
    before_action :expire_data_memos

    # Focus slot: the message composer. Enter submits, shift+enter inserts a newline.
    slot(:composer) { TextArea.new(height: 3, width: transcript_width, enter_newline: false, placeholder: composer_placeholder) }

    # Focus slot: the invite-code entry inside the add-contact modal.
    slot(:add_contact_input) { TextInput.new(width: 52, placeholder: "paste an invite code") }
    on_submit :add_contact_input, :add_contact_input_submitted
    on_cancel :add_contact_input, :add_contact_input_cancelled

    # Self-destruct presets the timer command cycles through, in seconds.
    TTL_PRESETS = [0, 5 * 60, 60 * 60, 24 * 60 * 60].freeze
    TTL_LABELS = {0 => "off", 300 => "5 minutes", 3600 => "1 hour", 86_400 => "24 hours"}.freeze

    def show
      return navigate :onboarding unless Store.unlocked?

      composer.width = transcript_width
      composer.placeholder = composer_placeholder
      transcript = build_transcript
      persist_view_state(transcript)
      clear_active_unread
      render :show,
        sidebar: conversation_list,
        transcript: transcript,
        composer: composer,
        active: active_conversation,
        status: connection_status,
        add_contact: add_contact_open? ? add_contact_input : nil,
        modal: current_modal,
        alert: key_change_alert,
        recording_elapsed: recording_elapsed,
        typing: active_conversation ? typing_in?(active_conversation.key) : false,
        palette: command_palette
    end

    def open_add_contact
      dismiss_command_palette
      session[:add_contact_open] = true
      focus.push_scope([:add_contact_input], origin: :modal)
      show
    end

    def add_contact_input_submitted(value)
      invite = Invite.decode(value.strip)
      AddContactFromInvite.new(my_fingerprint: my_fingerprint, my_name: my_display_name,
        hub: hub).call(invite)
      close_add_contact
      show_toast(add_contact_toast(invite))
      reload_conversations
      show
    rescue Invite::Malformed
      show_toast("That isn't a valid invite code", kind: :warn)
      add_contact_input.clear!
      show
    end

    def add_contact_input_cancelled
      close_add_contact
      show
    end

    def show_my_invite
      dismiss_command_palette
      code = hub ? hub.invite_code(name: my_display_name) : "(offline — reconnect to generate)"
      show_toast("Your invite code copied to the transcript")
      Conversation.find_or_create_by!(key: "self:notes") { |c| c.title = "My invite code" }
        .messages.create!(direction: "incoming", body: code, status: "delivered",
          sent_at: Time.now.utc, content_id: SecureRandom.uuid)
      reload_conversations
      show
    end

    def send_message
      conversation = active_conversation
      text = composer.value
      return no_conversation_to_send_to if conversation.nil? && !text.strip.empty?
      return show if conversation.nil? || text.strip.empty?

      append_outgoing(conversation, text)
      composer.clear!
      @last_composer_value = ""
      chat_state.follow = true
      show
    end

    def cycle_message_ttl
      dismiss_command_palette
      conversation = active_conversation
      return show_no_conversation_for_ttl unless conversation

      index = TTL_PRESETS.index(conversation.ttl) || 0
      conversation.update!(ttl: TTL_PRESETS[(index + 1) % TTL_PRESETS.length])
      show_toast("Message timer: #{TTL_LABELS.fetch(conversation.ttl)}")
      show
    end

    def retry_failed
      dismiss_command_palette
      count = Message.where(direction: "outgoing", status: "failed", kind: "text")
        .update_all(status: "pending")
      Redeliver.new(hub: hub).call if hub && connection_status == "online"
      show_toast(count.zero? ? "No failed messages" : "Retrying #{count} message#{"s" if count != 1}")
      show
    end

    def scroll_page_up
      chat_state.follow = false
      chat_state.transcript_offset = [chat_state.transcript_offset - transcript_height, 0].max
      show
    end

    def scroll_page_down
      chat_state.transcript_offset += transcript_height
      show
    end

    def scroll_to_bottom
      chat_state.follow = true
      show
    end

    private

    # The sidebar hosts conversations, not routes: j/k move the cursor, enter
    # activates the highlighted conversation and jumps to the composer.
    # Escape cancels an active recording from here too — the content-scoped
    # binding only sees escapes once the composer has focus.
    def dispatch_sidebar_key
      return cancel_recording if key_name == :escape && recording?

      case key_name
      when :j, :down then move_cursor(+1)
      when :k, :up then move_cursor(-1)
      when :enter then activate_cursor_conversation
      when :escape, :tab then focus_content
      else render_default_action
      end
      response
    end

    def move_cursor(delta)
      count = conversations.length
      return render_default_action if count.zero?

      chat_state.cursor_index = (chat_state.cursor_index + delta).clamp(0, count - 1)
      render_default_action
    end

    def activate_cursor_conversation
      conversation = conversations[chat_state.cursor_index]
      if conversation
        composer_drafts[composer_key] = composer.value
        chat_state.active_conversation_id = conversation.id
        @active_conversation = nil
        composer.value = composer_drafts.fetch(composer_key, "")
        @last_composer_value = composer.value
        reset_transcript
        focus_content
      else
        render_default_action
      end
    end

    def reset_transcript
      chat_state.transcript_offset = 0
      chat_state.follow = true
    end

    def append_outgoing(conversation, text)
      now = Time.now.utc
      message = conversation.messages.create!(
        direction: "outgoing", body: text, status: "pending",
        sent_at: now, content_id: SecureRandom.uuid,
        expires_at: conversation.ttl.positive? ? now + conversation.ttl : nil
      )
      conversation.touch_activity
      transmit(conversation, message, text)
    end

    def no_conversation_to_send_to
      show_toast("Add a contact first — ctrl+p → Add contact (or Copy my invite code to share yours)",
        kind: :warn)
      show
    end

    # Fan the text out to every participant's device bundle. With no recipients
    # (contact not yet resolved) the message stays local as pending — say so
    # instead of looking like a successful send.
    def transmit(conversation, message, text)
      bundles = recipient_bundles(conversation)
      if bundles.empty?
        show_toast("No recipients for this conversation — message saved on this device only",
          kind: :warn)
        return
      end

      content = Protocol::Content.new(kind: "text", conversation: conversation.key,
        body: text, id: message.content_id, ttl: conversation.ttl)
      deliver_content(content, to_bundles: bundles)
    end

    def recipient_bundles(conversation)
      RecipientBundles.for(conversation, my_fingerprint: my_fingerprint,
        my_mailbox: hub&.device&.mailbox)
    end

    def conversation_ttl
      active_conversation&.ttl.to_i
    end

    def show_no_conversation_for_ttl
      show_toast("Open a conversation first", kind: :warn)
      show
    end

    def conversations
      @conversations ||= Conversation.recent_first.to_a
    end

    # before_action hook: data reads re-query on the next access. Hooks run
    # before key/timer/task actions; component-result actions skip hooks but
    # reload explicitly after their own mutations.
    def expire_data_memos
      @conversations = nil
      @active_conversation = nil
      @pending_requests = nil
    end

    def active_conversation
      @active_conversation ||=
        conversations.find { |c| c.id == chat_state.active_conversation_id } || conversations.first
    end

    # Each modal-owning concern contributes a spec here; the first open one wins.
    def current_modal
      contact_requests_modal || verification_modal || rooms_modal || relays_modal ||
        attachments_modal || enrollment_modal || qr_invite_modal
    end

    def conversation_list
      ConversationList.new(
        conversations: conversations,
        cursor_index: chat_state.cursor_index,
        active_id: active_conversation&.id,
        focused: sidebar_focused?,
        request_count: ContactRequest.inbox.count,
        theme: theme
      )
    end

    # Rebuilt every render: a memoized transcript would freeze the moment it
    # was built and never show messages that land afterwards.
    def build_transcript
      messages = active_conversation ? active_conversation.messages.unexpired.chronological.to_a : []
      Transcript.new(
        messages: messages,
        width: transcript_width, height: transcript_height,
        offset: chat_state.transcript_offset, follow: chat_state.follow,
        image_blocks: transcript_image_blocks(messages),
        theme: theme
      )
    end

    # The composer draft is per-conversation, so switching chats keeps each
    # draft. Drafts for inactive conversations live here; the active one lives
    # in the composer component itself.
    def composer_drafts
      @composer_drafts ||= {}
    end

    def composer_key
      active_conversation&.id || "none"
    end

    def composer_placeholder
      active_conversation ? "Message #{active_conversation.display_title}…" : "No conversation selected"
    end

    def add_contact_open?
      session[:add_contact_open]
    end

    # Clears the memoized input so the next open starts empty.
    def close_add_contact
      session[:add_contact_open] = false
      add_contact_input.clear!
      focus.pop_scope
    end

    def reload_conversations
      @conversations = nil
      @active_conversation = nil
    end

    # Looking at the bottom of the active conversation counts as reading it.
    def clear_active_unread
      conversation = active_conversation
      return unless conversation && chat_state.follow && conversation.unread_count.positive?

      conversation.update!(unread_count: 0)
    end

    # A throttled ephemeral typing signal on composer changes. ttl 1 keeps the
    # relay from holding stale hints for offline peers (SPEC: typing is never
    # meaningfully queued).
    def maybe_send_typing(previous, current)
      return if current == previous || current.strip.empty?
      return unless hub && active_conversation

      now = Time.now.to_f
      return if now - (session[:typing_sent_at] || 0.0) < 4

      session[:typing_sent_at] = now
      content = Protocol::Content.new(kind: "typing", conversation: active_conversation.key,
        body: {}, ttl: 1)
      deliver_content(content, to_bundles: recipient_bundles(active_conversation))
    end

    def my_display_name
      "me"
    end

    # The invite add notifies the invitee with a contact request; say what
    # happens next, keyed on whether the relay is reachable right now.
    def add_contact_toast(invite)
      return "Added #{invite.name} — they can reply once they accept your contact request" if connection_status == "online"

      "Added #{invite.name} — your contact request sends when you reconnect"
    end

    # Per-render write-back: the viewport's clamped scroll position, and the
    # typing-signal comparison against the draft as of the previous render.
    def persist_view_state(transcript)
      chat_state.transcript_offset = transcript.offset
      chat_state.follow = transcript.at_bottom?
      maybe_send_typing(@last_composer_value, composer.value)
      @last_composer_value = composer.value
    end

    def transcript_width
      [screen.width - 32, 40].max
    end

    def transcript_height
      [screen.height - 13, 5].max
    end

    def chat_state
      state(:chat, ChatState)
    end
  end
end
