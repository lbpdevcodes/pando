# frozen_string_literal: true

require "securerandom"

module Pando
  class ChatController < ApplicationController
    focus_ring :sidebar, :composer

    key "page_up", :scroll_page_up, scope: :global
    key "page_down", :scroll_page_down, scope: :global
    key "end", :scroll_to_bottom, scope: :global
    # TextArea with enter_newline: false reserves plain Enter for its host —
    # this content-scoped binding is the send action (sidebar Enter still selects).
    key "enter", :send_message

    command "Add contact", :open_add_contact
    command "Copy my invite code", :show_my_invite

    def show
      return navigate_to("/onboarding") unless Store.unlocked?

      persist_component_state
      render :show,
        sidebar: conversation_list,
        transcript: transcript,
        composer: composer,
        active: active_conversation,
        status: connection_status,
        add_contact: add_contact_open? ? add_contact_input : nil,
        palette: command_palette
    end

    def open_add_contact
      close_command_palette
      session[:add_contact_open] = true
      focus.push_scope([:add_contact_input], origin: :modal)
      show
    end

    # Focus slot: the invite-code entry inside the add-contact modal.
    def add_contact_input
      @add_contact_input ||= Charming::Components::TextInput.new(
        value: add_contact_state[:value], width: 52, placeholder: "paste an invite code"
      )
    end

    def add_contact_input_submitted(value)
      invite = Invite.decode(value.strip)
      AddContact.new(my_fingerprint: my_fingerprint).call(invite)
      close_add_contact
      show_toast("Added #{invite.name}")
      reload_conversations
      show
    rescue Invite::Malformed
      show_toast("That isn't a valid invite code", kind: :warn)
      add_contact_state[:value] = ""
      @add_contact_input = nil
      show
    end

    def add_contact_input_cancelled
      close_add_contact
      show
    end

    def show_my_invite
      close_command_palette
      code = hub ? hub.invite_code(name: my_display_name) : "(offline — reconnect to generate)"
      show_toast("Your invite code copied to the transcript")
      Conversation.find_or_create_by!(key: "self:notes") { |c| c.title = "My invite code" }
        .messages.create!(direction: "incoming", body: code, status: "delivered",
          sent_at: Time.now.utc, content_id: SecureRandom.uuid)
      reload_conversations
      show
    end

    # Focus slot: the message composer. Enter submits, shift+enter inserts a newline.
    def composer
      @composer ||= Charming::Components::TextArea.new(
        value: composer_state[:value], height: 3, width: transcript_width,
        enter_newline: false, placeholder: composer_placeholder
      )
    end

    def send_message
      conversation = active_conversation
      text = composer.value
      return show if conversation.nil? || text.strip.empty?

      append_outgoing(conversation, text)
      composer_state[:value] = ""
      @composer = nil
      chat_state.follow = true
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
    def dispatch_sidebar_key
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
        chat_state.active_conversation_id = conversation.id
        reset_transcript
        focus_content
      else
        render_default_action
      end
    end

    def reset_transcript
      chat_state.transcript_offset = 0
      chat_state.follow = true
      @transcript = nil
    end

    def append_outgoing(conversation, text)
      message = conversation.messages.create!(
        direction: "outgoing", body: text, status: "pending",
        sent_at: Time.now.utc, content_id: SecureRandom.uuid
      )
      conversation.touch_activity
      transmit(conversation, message, text)
    end

    # Fan the text out to every participant's device bundle. With no recipients
    # (contact not yet resolved) the message stays local as pending.
    def transmit(conversation, message, text)
      bundles = recipient_bundles(conversation)
      return if bundles.empty?

      content = Protocol::Content.new(kind: "text", conversation: conversation.key,
        body: text, id: message.content_id, ttl: conversation_ttl)
      deliver_content(content, to_bundles: bundles)
    end

    def recipient_bundles(conversation)
      conversation.contacts.filter_map(&:device_bundle)
    end

    def conversation_ttl
      0
    end

    def conversations
      @conversations ||= Conversation.recent_first.to_a
    end

    def active_conversation
      @active_conversation ||=
        conversations.find { |c| c.id == chat_state.active_conversation_id } || conversations.first
    end

    def conversation_list
      ConversationList.new(
        conversations: conversations,
        cursor_index: chat_state.cursor_index,
        active_id: active_conversation&.id,
        focused: sidebar_focused?,
        theme: theme
      )
    end

    def transcript
      @transcript ||= Transcript.new(
        messages: active_conversation ? active_conversation.messages.chronological.to_a : [],
        width: transcript_width, height: transcript_height,
        offset: chat_state.transcript_offset, follow: chat_state.follow,
        theme: theme
      )
    end

    # The composer draft is per-conversation, so switching chats keeps each draft.
    def composer_key
      :"composer_#{active_conversation&.id || "none"}"
    end

    def composer_placeholder
      active_conversation ? "Message #{active_conversation.display_title}…" : "No conversation selected"
    end

    def add_contact_open?
      session[:add_contact_open]
    end

    def close_add_contact
      session[:add_contact_open] = false
      add_contact_state[:value] = ""
      @add_contact_input = nil
      focus.pop_scope
    end

    def reload_conversations
      @conversations = nil
      @active_conversation = nil
    end

    def my_display_name
      "me"
    end

    def persist_component_state
      chat_state.transcript_offset = transcript.offset
      chat_state.follow = transcript.at_bottom?
      composer_state[:value] = composer.value
      add_contact_state[:value] = add_contact_input.value if add_contact_open?
    end

    def composer_state
      component_state(composer_key, value: "")
    end

    def add_contact_state
      component_state(:add_contact, value: "")
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
