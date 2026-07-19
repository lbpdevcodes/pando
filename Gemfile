# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Requires charming ~> 0.2.3 (viewport follow-mode + Kitty image-deletion), pinned in
# the gemspec. Path-sourced only until 0.2.3 is pushed to RubyGems — after `gem push`,
# delete this line and `bundle install` to depend on the published gem.
gem "charming", path: "../charming"

group :development, :test do
  gem "irb"     # `charming console` (not a default gem on Ruby 4.0+)
  gem "rake", "~> 13.0"
  gem "rspec", "~> 3.13"
  gem "standard", "~> 1.50"
end
