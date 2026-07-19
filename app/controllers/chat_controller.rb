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

    def show
      return navigate_to("/onboarding") unless Store.unlocked?

      persist_component_state
      render :show,
        sidebar: conversation_list,
        transcript: transcript,
        composer: composer,
        active: active_conversation,
        palette: command_palette
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
      conversation.messages.create!(
        direction: "outgoing", body: text, status: "pending",
        sent_at: Time.now.utc, content_id: SecureRandom.uuid
      )
      conversation.touch_activity
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

    def persist_component_state
      chat_state.transcript_offset = transcript.offset
      chat_state.follow = transcript.at_bottom?
      composer_state[:value] = composer.value
    end

    def composer_state
      component_state(composer_key, value: "")
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
