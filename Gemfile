# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Path-sourced until the viewport follow-mode and Kitty image-deletion releases ship.
gem "charming", path: "../charming"

group :development, :test do
  gem "irb"     # `charming console` (not a default gem on Ruby 4.0+)
  gem "rake", "~> 13.0"
  gem "rspec", "~> 3.13"
  gem "standard", "~> 1.50"
end
