# frozen_string_literal: true

module Pando
  # ContactRequestsUi is the chat screen's first-contact surface: the requests
  # inbox modal (accept/decline), directory lookup by fingerprint, and the
  # discoverability toggle. Directory HTTP runs on a background task; the
  # request itself is recorded and sent from the UI thread when the task lands.
  module ContactRequestsUi
    def self.included(base)
      base.command "Contact requests", :open_requests
      base.command "Find contact by fingerprint", :open_find_contact
      base.command "Toggle discoverability", :toggle_discoverability
      base.on_task :discover_contact, action: :discover_contact_finished

      base.slot(:requests_list) { RequestList.new(requests: [], theme: theme) }
      base.slot(:find_contact_input) { TextInput.new(width: 32, placeholder: "16-hex fingerprint") }

      base.on_select :requests_list, :requests_list_selected
      base.on_cancel :requests_list, :requests_list_cancelled
      base.on_submit :find_contact_input, :find_contact_input_submitted
      base.on_cancel :find_contact_input, :find_contact_input_cancelled
    end

    def open_requests
      dismiss_command_palette
      requests_list.items = pending_requests
      session[:requests_open] = true
      focus.push_scope([:requests_list], origin: :modal)
      show
    end

    def requests_list_selected(value)
      action, request = value
      (action == :accept) ? accept_request(request) : decline_request(request)
      reload_requests
      close_requests if pending_requests.empty?
      show
    end

    def requests_list_cancelled
      close_requests
      show
    end

    def open_find_contact
      dismiss_command_palette
      session[:find_contact_open] = true
      focus.push_scope([:find_contact_input], origin: :modal)
      show
    end

    def find_contact_input_submitted(value)
      fingerprint = value.strip.downcase
      return reject_fingerprint unless fingerprint.match?(/\A\h{16}\z/)

      close_find_contact
      start_discovery(fingerprint)
      show
    end

    def find_contact_input_cancelled
      close_find_contact
      show
    end

    def discover_contact_finished
      fingerprint = session.delete(:discover_fp)
      if event.error?
        show_toast("Directory lookup failed", kind: :error)
      elsif send_request(fingerprint)
        show_toast("Contact request sent")
      else
        show_toast("No discoverable device for that fingerprint", kind: :warn)
      end
      show
    end

    def toggle_discoverability
      dismiss_command_palette
      flag = Setting.get("discoverable") != "1"
      Setting.put("discoverable", flag ? "1" : "0")
      hub&.discoverable = flag
      show_toast(flag ? "You are now discoverable by fingerprint" : "You are hidden from the directory")
      show
    end

    private

    def accept_request(request)
      AcceptContactRequest.new(my_fingerprint: my_fingerprint, my_name: my_display_name, hub: hub)
        .call(request)
      show_toast("Now contacts with #{request.display_name}")
      reload_conversations
    end

    def decline_request(request)
      request.update!(status: "declined")
      show_toast("Declined #{request.display_name}", kind: :info)
    end

    def reject_fingerprint
      show_toast("A fingerprint is 16-hex characters", kind: :warn)
      find_contact_input.clear!
      show
    end

    # The lookup happens off-thread; the client is built up front — no AR
    # access inside the task block.
    def start_discovery(fingerprint)
      return show_toast("Offline — can't search the directory", kind: :warn) unless hub

      session[:discover_fp] = fingerprint
      client = directory_client
      run_task(:discover_contact) { client.discover(fingerprint) }
      show_toast("Searching the directory…", kind: :info)
    end

    def send_request(fingerprint)
      SendContactRequest.new(my_fingerprint: my_fingerprint, my_name: my_display_name, hub: hub)
        .call(fingerprint: fingerprint, bundles: event.value)
    end

    def contact_requests_modal
      return requests_modal if session[:requests_open]
      return find_contact_modal if session[:find_contact_open]

      nil
    end

    def requests_modal
      {title: "Contact requests (#{pending_requests.length})", content: requests_list,
       help: "enter/a accept · d decline · esc close"}
    end

    def find_contact_modal
      {title: "Find contact", content: find_contact_input, help: "enter search · esc cancel"}
    end

    def pending_requests
      @pending_requests ||= ContactRequest.inbox.to_a
    end

    def reload_requests
      @pending_requests = nil
      requests_list.items = pending_requests
    end

    def close_requests
      session[:requests_open] = false
      focus.pop_scope
    end

    # Clears the memoized input so the next open starts empty.
    def close_find_contact
      session[:find_contact_open] = false
      find_contact_input.clear!
      focus.pop_scope
    end
  end
end
