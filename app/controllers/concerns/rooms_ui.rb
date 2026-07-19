# frozen_string_literal: true

module Pando
  # RoomsUi is the chat screen's room surface: create a room, invite a contact
  # to the active room (matched by name or fingerprint prefix — contact names
  # are encrypted, so matching happens in Ruby), and show membership churn.
  # Inviting needs the wire, so it requires a live hub.
  module RoomsUi
    def self.included(base)
      base.command "New room", :open_new_room
      base.command "Invite to room", :open_room_invite
    end

    def open_new_room
      close_command_palette
      session[:new_room_open] = true
      focus.push_scope([:new_room_input], origin: :modal)
      show
    end

    # Focus slot: the room-name entry inside the new-room modal.
    def new_room_input
      @new_room_input ||= Charming::Components::TextInput.new(
        value: new_room_state[:value], width: 32, placeholder: "room name"
      )
    end

    def new_room_input_submitted(value)
      name = value.strip
      return show if name.empty?

      room = CreateRoom.new(my_fingerprint: my_fingerprint).call(name: name)
      close_new_room
      chat_state.active_conversation_id = room.id
      reload_conversations
      show_toast("Created #{name} — invite contacts with ctrl+p")
      show
    end

    def new_room_input_cancelled
      close_new_room
      show
    end

    def open_room_invite
      close_command_palette
      return not_a_room unless active_conversation&.room?
      return offline_for_invite unless hub

      session[:room_invite_open] = true
      focus.push_scope([:room_invite_input], origin: :modal)
      show
    end

    # Focus slot: the contact entry inside the invite modal.
    def room_invite_input
      @room_invite_input ||= Charming::Components::TextInput.new(
        value: room_invite_state[:value], width: 32, placeholder: "contact name or fingerprint"
      )
    end

    def room_invite_input_submitted(value)
      contact = resolve_contact(value.strip)
      return unknown_invitee unless contact

      room = active_conversation
      close_room_invite
      result = InviteToRoom.new(my_fingerprint: my_fingerprint, my_name: my_display_name,
        hub: hub).call(room, contact)
      show_toast(result ? "Invited #{contact.display_name} to #{room.display_title}" :
        "#{contact.display_name} is already a member", kind: result ? :success : :warn)
      show
    end

    def room_invite_input_cancelled
      close_room_invite
      show
    end

    private

    def not_a_room
      show_toast("The active conversation isn't a room — create one with ctrl+p", kind: :warn)
      show
    end

    def offline_for_invite
      show_toast("Offline — inviting needs a relay connection", kind: :warn)
      show
    end

    def resolve_contact(query)
      return nil if query.empty?

      needle = query.downcase
      Contact.find_each.find do |contact|
        contact.display_name.downcase == needle || contact.fingerprint.start_with?(needle)
      end
    end

    def unknown_invitee
      show_toast("No contact matches that name or fingerprint", kind: :warn)
      room_invite_state[:value] = ""
      @room_invite_input = nil
      show
    end

    def rooms_modal
      return new_room_modal if session[:new_room_open]
      return room_invite_modal if session[:room_invite_open]

      nil
    end

    def new_room_modal
      {title: "New room", content: new_room_input, help: "enter create · esc cancel"}
    end

    def room_invite_modal
      {title: "Invite to #{active_conversation&.display_title}", content: room_invite_input,
       help: "enter invite · esc cancel"}
    end

    def close_new_room
      session[:new_room_open] = false
      new_room_state[:value] = ""
      @new_room_input = nil
      focus.pop_scope
    end

    def close_room_invite
      session[:room_invite_open] = false
      room_invite_state[:value] = ""
      @room_invite_input = nil
      focus.pop_scope
    end

    def persist_rooms_state
      new_room_state[:value] = new_room_input.value if session[:new_room_open]
      room_invite_state[:value] = room_invite_input.value if session[:room_invite_open]
    end

    def new_room_state
      component_state(:new_room, value: "")
    end

    def room_invite_state
      component_state(:room_invite, value: "")
    end
  end
end
