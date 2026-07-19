# frozen_string_literal: true

require "fileutils"
require "json"

module Pando
  # Settings is the tiny non-secret preferences file (currently just the
  # theme). Deliberately NOT Charming's persist_session — that would serialize
  # the whole session, including the unlocked identity's private keys, to
  # plaintext JSON. Only explicitly whitelisted values ever land here.
  module Settings
    module_function

    def load
      return {} unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      {}
    end

    def save(**values)
      FileUtils.mkdir_p(Store.root)
      merged = load.merge(values.transform_keys(&:to_s).transform_values(&:to_s))
      File.write(path, JSON.generate(merged))
      File.chmod(0o600, path)
    end

    def path
      File.join(Store.root, "settings.json")
    end
  end
end
