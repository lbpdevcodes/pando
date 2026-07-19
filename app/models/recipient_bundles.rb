# frozen_string_literal: true

module Pando
  # RecipientBundles is THE recipient-resolution choke point: a conversation
  # fans out to every known device of every participant, plus our own account's
  # other devices so history stays in sync across enrollments. Our own
  # fingerprint has no Contact row, so "everyone but this device" falls out of
  # the join plus the mailbox filter.
  class RecipientBundles
    def self.for(conversation, my_fingerprint:, my_mailbox:)
      participants = conversation.contacts.pluck(:fingerprint)
        .flat_map { |fingerprint| ContactDevice.bundles_for(fingerprint) }
      own = ContactDevice.bundles_for(my_fingerprint)
        .reject { |bundle| bundle.mailbox == my_mailbox }
      participants + own
    end
  end
end
