# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"

module Pando
  module Client
    # Enrollment pairs a new device with an existing account through a relay
    # rendezvous slot. The new device deposits an offer (its public keys); an
    # enrolled device answers with a grant: the account seed AND a bootstrap
    # export (contacts, rooms, own devices) sealed anonymously to the offer's
    # encryption key — the new device starts with an empty database and could
    # otherwise address no one.
    #
    # The 6-digit code is low-entropy and the offer unauthenticated: an
    # attacker racing the code could receive the sealed seed IF the approver
    # approves their key. The safety code (a hash of the offered keys, shown on
    # both screens for the human to compare) is the v1 defense — approvers must
    # check it.
    module Enrollment
      class << self
        # Seam for specs/journeys: builds the rendezvous transport for a relay.
        attr_writer :rendezvous_factory

        def rendezvous_factory
          @rendezvous_factory ||= ->(url, token) { RendezvousClient.new(url, token: token) }
        end

        def rendezvous_for(url, token: nil)
          rendezvous_factory.call(url, token)
        end
      end

      module_function

      def safety_code_for(sign_b64, box_b64)
        Digest::SHA256.hexdigest("#{sign_b64}|#{box_b64}")[0, 8]
      end

      # The new-device half: deposit an offer, poll for the grant, open it.
      class Offer
        attr_reader :device, :code

        def initialize(rendezvous:, device: Crypto::Device.generate,
          code: format("%06d", SecureRandom.random_number(1_000_000)))
          @rendezvous = rendezvous
          @device = device
          @code = code
        end

        def deposit!
          @rendezvous.deposit(code, payload)
        end

        def safety_code
          Enrollment.safety_code_for(*encoded_keys)
        end

        # :waiting until the grant lands, :denied once the slot vanishes, or
        # {identity:, import:} — the sealed seed opened with OUR device key.
        def poll
          payloads = @rendezvous.fetch(code)
          return :denied if payloads.empty?

          grant = payloads.find { |p| p.is_a?(Hash) && p["type"] == "enroll-grant" }
          return :waiting unless grant

          open_grant(grant)
        rescue RendezvousClient::Error
          :denied
        end

        def cleanup
          @rendezvous.delete(code)
        end

        private

        def payload
          sign, box = encoded_keys
          {"v" => 1, "type" => "enroll-offer", "sign" => sign, "box" => box,
           "mailbox" => device.mailbox, "safety" => safety_code}
        end

        def encoded_keys
          [[device.signing_public_key].pack("m0"), [device.encryption_public_key].pack("m0")]
        end

        def open_grant(grant)
          blob = JSON.parse(Crypto::SealedTransfer.open(grant["sealed"].unpack1("m0"), with: device))
          account = Crypto::Account.from_seed(blob.fetch("account_seed").unpack1("m0"))
          {identity: Crypto::Identity.to_h(account: account, device: device), import: blob}
        end
      end

      # The enrolled-device half: inspect the offer, approve (seal the seed +
      # bootstrap export to the offered key) or deny (delete the slot).
      class Grant
        def initialize(identity:, rendezvous:)
          @identity = identity
          @rendezvous = rendezvous
        end

        def fetch_offer(code)
          @rendezvous.fetch(code).find { |p| p.is_a?(Hash) && p["type"] == "enroll-offer" }
        rescue RendezvousClient::Error
          nil
        end

        # Recomputed from the offered keys, NOT trusted from the payload — the
        # approver compares this against the code on the new device's screen.
        def safety_code(offer)
          Enrollment.safety_code_for(offer["sign"], offer["box"])
        end

        def approve!(offer, code:, contacts: [], conversations: [], extra_own_devices: [])
          blob = {"account_seed" => [account.seed].pack("m0"),
                  "contacts" => contacts, "conversations" => conversations,
                  "own_devices" => own_device_bundles(extra_own_devices)}
          sealed = Crypto::SealedTransfer.seal(JSON.generate(blob),
            to: offer.fetch("box").unpack1("m0"))
          @rendezvous.deposit(code,
            {"v" => 1, "type" => "enroll-grant", "sealed" => [sealed].pack("m0")})
        end

        def deny!(code)
          @rendezvous.delete(code)
        end

        private

        def account
          @account ||= Crypto::Identity.account_from(@identity)
        end

        def device
          @device ||= Crypto::Identity.device_from(@identity)
        end

        # The granter's own bundle at minimum (plus any siblings the caller
        # knows of), so the new device can fan out to them from the start.
        def own_device_bundles(extra)
          mine = Crypto::DeviceBundle.issue(device: device, account: account).to_h
          ([mine] + extra).uniq { |hash| hash["mailbox"] }
        end
      end
    end
  end
end
