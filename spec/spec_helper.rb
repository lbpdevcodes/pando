# frozen_string_literal: true

ENV["CHARMING_ENV"] ||= "test"

require "pando"

# Prepare the test database, preferring the dumped schema over replaying migrations.
schema = File.expand_path("../db/schema.rb", __dir__)
if File.exist?(schema)
  load schema
else
  ActiveRecord::MigrationContext.new(File.expand_path("../db/migrate", __dir__)).migrate
end

# A fixed data key so encrypted columns work in tests without a keyring unlock.
TEST_DATA_KEY = RbNaCl::Hash.sha256("pando test data key")

RSpec.configure do |config|
  config.before(:each) { Pando::Store.data_key = TEST_DATA_KEY }

  # Never let the test host's terminal (e.g. running specs inside Ghostty)
  # enable real graphics — specs that want Kitty inject their own Terminal.
  config.before(:each) { Pando::Graphics.terminal = Charming::Image::Terminal.new(env: {}) }

  # Roll back database writes after each example so tests stay isolated.
  config.around(:each) do |example|
    ActiveRecord::Base.transaction(requires_new: true) do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
