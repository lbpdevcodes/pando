# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Pando
  module Client
    # RendezvousClient speaks the relay's rendezvous slots over HTTP — the
    # short-lived two-payload mailboxes enrollment pairs through.
    class RendezvousClient
      Error = Class.new(StandardError)

      def initialize(base_url, token: nil)
        @base_url = base_url
        @token = token
      end

      def deposit(code, payload)
        request = Net::HTTP::Post.new(uri(code), headers)
        request.body = JSON.generate({"payload" => payload})
        perform(request)
        true
      end

      def fetch(code)
        response = perform(Net::HTTP::Get.new(uri(code), headers))
        JSON.parse(response.body).fetch("payloads")
      end

      def delete(code)
        perform(Net::HTTP::Delete.new(uri(code), headers))
        true
      end

      private

      attr_reader :base_url, :token

      def uri(code)
        URI.join(base_url, "/v1/rendezvous/#{code}")
      end

      def headers
        token ? {"x-pando-relay-token" => token} : {}
      end

      def perform(request)
        target = request.uri
        response = Net::HTTP.start(target.host, target.port, read_timeout: 5, open_timeout: 5) do |http|
          http.request(request)
        end
        raise Error, "relay responded #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response
      end
    end
  end
end
