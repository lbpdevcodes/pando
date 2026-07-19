# frozen_string_literal: true

module Pando
  module Relay
    # MailboxRegistry tracks which mailboxes have live subscribed sessions, so a
    # publish can be forwarded instead of queued. Mutex-guarded: sessions register
    # from their own fibers/threads.
    class MailboxRegistry
      def initialize
        @sessions = Hash.new { |hash, key| hash[key] = [] }
        @mutex = Mutex.new
      end

      def register(mailbox, session)
        @mutex.synchronize { @sessions[mailbox] << session }
      end

      def unregister(mailbox, session)
        @mutex.synchronize { @sessions[mailbox].delete(session) }
      end

      def sessions_for(mailbox)
        @mutex.synchronize { @sessions[mailbox].dup }
      end
    end
  end
end
