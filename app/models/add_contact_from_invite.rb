# frozen_string_literal: true

module Pando
  # AddContactFromInvite is the invite-code add: AddContact pins the invitee
  # locally, then SendContactRequest tells them we exist — our bundle is what
  # lets them reply. Accepting our request creates the contact both ways, so a
  # one-sided paste becomes a two-way conversation.
  class AddContactFromInvite
    def initialize(my_fingerprint:, my_name:, hub: nil)
      @my_fingerprint = my_fingerprint
      @my_name = my_name
      @hub = hub
    end

    def call(invite)
      already_known = Contact.exists?(fingerprint: invite.fingerprint)
      contact, conversation = AddContact.new(my_fingerprint: my_fingerprint).call(invite)
      notify(invite) if hub && !already_known
      [contact, conversation]
    end

    private

    attr_reader :my_fingerprint, :my_name, :hub

    def notify(invite)
      SendContactRequest.new(my_fingerprint: my_fingerprint, my_name: my_name, hub: hub)
        .call(fingerprint: invite.fingerprint, bundles: [invite.bundle])
    end
  end
end
