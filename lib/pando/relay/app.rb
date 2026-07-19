# frozen_string_literal: true

require "json"
require "async"
require "async/http/endpoint"
require "async/http/server"
require "async/websocket/adapters/http"
require "protocol/http/response"

module Pando
  module Relay
    # App is the whole relay process: the WebSocket endpoint for message traffic and
    # the small HTTP surface (directory publish/discover, rendezvous, health). An
    # optional relay token gates every request. Built directly on async-http so it
    # embeds in a spec, a script, or the pando-relay executable identically.
    class App
      def self.serve(app, host:, port:)
        Async do
          endpoint = Async::HTTP::Endpoint.parse("http://#{host}:#{port}")
          Async::HTTP::Server.new(app, endpoint).run
        end
      end

      def initialize(db_path:, limits: Protocol::Limits.default, token: nil)
        @directory = Directory.new(db_path)
        @queue = QueueStore.new(db_path, limits: limits)
        @registry = MailboxRegistry.new
        @rendezvous = Rendezvous.new
        @limits = limits
        @token = token
      end

      def call(request)
        return respond(401, error: "invalid relay token") unless authorized?(request)

        route(request) || respond(404, error: "not found")
      rescue JSON::ParserError
        respond(400, error: "malformed body")
      end

      private

      attr_reader :directory, :queue, :registry, :rendezvous, :limits, :token

      def route(request)
        # async-http yields ASCII-8BIT paths; sqlite3 binds binary strings as
        # BLOBs, which silently never match TEXT columns — normalize up front.
        segments = request.path.delete_prefix("/").split("/")
          .map { |segment| segment.dup.force_encoding(Encoding::UTF_8) }
        case [request.method, segments.first(2)]
        in ["GET", ["v1", "ws"]] then upgrade(request)
        in ["GET", ["v1", "health"]] then respond(200, ok: true)
        in ["PUT", ["v1", "directory"]] then publish(request)
        in ["GET", ["v1", "directory"]] then discover(segments[2])
        in [method, ["v1", "rendezvous"]] then rendezvous_route(method, segments[2], request)
        else nil
        end
      end

      def upgrade(request)
        Async::WebSocket::Adapters::HTTP.open(request) do |connection|
          SocketSession.new(
            connection: connection, directory: directory, queue: queue,
            registry: registry, limits: limits
          ).run
        end
      end

      def publish(request)
        body = JSON.parse(request.read)
        directory.publish(body.fetch("bundle"), discoverable: body.fetch("discoverable", false))
        respond(204)
      rescue Directory::InvalidBundle, KeyError => error
        respond(422, error: error.message)
      end

      def discover(fingerprint)
        return nil unless fingerprint

        respond(200, bundles: directory.discover(fingerprint: fingerprint))
      end

      def rendezvous_route(method, code, request)
        return nil unless code

        case method
        when "POST" then deposit(code, request)
        when "GET" then respond(200, payloads: rendezvous.fetch(code, now: now))
        when "DELETE" then rendezvous.delete(code) && respond(204)
        end
      end

      def deposit(code, request)
        rendezvous.deposit(code, JSON.parse(request.read).fetch("payload"), now: now)
        respond(204)
      rescue Rendezvous::SlotFull => error
        respond(409, error: error.message)
      end

      def authorized?(request)
        return true unless token

        request.headers["x-pando-relay-token"] == token
      end

      def respond(status, **payload)
        return ::Protocol::HTTP::Response[status, {}, []] if payload.empty?

        ::Protocol::HTTP::Response[status, {"content-type" => "application/json"}, [JSON.generate(payload)]]
      end

      def now
        Time.now.to_i
      end
    end
  end
end
