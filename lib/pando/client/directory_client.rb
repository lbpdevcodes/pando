# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Pando
  module Client
    # DirectoryClient speaks the relay's HTTP surface: publishing this device's
    # bundle (required before subscribing) and discovering contacts by fingerprint.
    class DirectoryClient
      Error = Class.new(StandardError)

      def initialize(base_url, token: nil)
        @base_url = base_url
        @token = token
      end

      def publish(bundle_hash, discoverable: false)
        request = Net::HTTP::Put.new(uri("/v1/directory"), headers)
        request.body = JSON.generate({"bundle" => bundle_hash, "discoverable" => discoverable})
        perform(request)
        true
      end

      def discover(fingerprint)
        response = perform(Net::HTTP::Get.new(uri("/v1/directory/#{fingerprint}"), headers))
        JSON.parse(response.body).fetch("bundles")
      end

      private

      attr_reader :base_url, :token

      def uri(path)
        URI.join(base_url, path)
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
