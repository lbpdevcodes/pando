# frozen_string_literal: true

require "optparse"

module Pando
  module Relay
    # CLI boots the relay from the pando-relay executable: flags/env for the bind
    # address, data directory, and optional access token, then serves until killed.
    class CLI
      DEFAULT_PORT = 8787

      def self.start(argv, output: $stdout)
        options = parse(argv)
        output.puts "pando-relay listening on #{options[:host]}:#{options[:port]} (db: #{options[:db]})"
        App.serve(
          App.new(db_path: options[:db], token: options[:token]),
          host: options[:host], port: options[:port]
        )
      end

      def self.parse(argv)
        options = defaults
        parser(options).parse(argv)
        options
      end

      def self.defaults
        {
          host: ENV.fetch("PANDO_RELAY_HOST", "0.0.0.0"),
          port: Integer(ENV.fetch("PANDO_RELAY_PORT", DEFAULT_PORT)),
          db: ENV.fetch("PANDO_RELAY_DB", File.expand_path("~/.pando/relay/relay.db")),
          token: ENV.fetch("PANDO_RELAY_TOKEN", nil)
        }
      end

      def self.parser(options)
        OptionParser.new do |opts|
          opts.banner = "Usage: pando-relay [options]"
          opts.on("--host HOST", "Bind address") { |value| options[:host] = value }
          opts.on("--port PORT", Integer, "Listen port") { |value| options[:port] = value }
          opts.on("--db PATH", "SQLite database path") { |value| options[:db] = value }
          opts.on("--token TOKEN", "Require this relay access token") { |value| options[:token] = value }
        end
      end
    end
  end
end
