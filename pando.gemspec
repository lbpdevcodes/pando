# frozen_string_literal: true

require_relative "lib/pando/version"

Gem::Specification.new do |spec|
  spec.name = "pando"
  spec.version = Pando::VERSION
  spec.summary = "Private, end-to-end encrypted terminal chat."
  spec.authors = ["Pando"]
  spec.email = ["lbpdev@proton.me"]
  spec.files = Dir.glob("{app,config,db,exe,lib}/**/*") + %w[README.md]
  spec.bindir = "exe"
  spec.executables = ["pando", "pando-relay"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 4.0.0"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.add_dependency "charming", "~> 0.4.0"
  spec.add_dependency "activerecord", "~> 8.1"
  spec.add_dependency "sqlite3", "~> 2.0"
  spec.add_dependency "rbnacl", "~> 7.1"
  spec.add_dependency "websocket-driver", "~> 0.8"
  spec.add_dependency "rqrcode", "~> 3.0"
  spec.add_dependency "chunky_png", "~> 1.4"
  spec.add_dependency "async-websocket", "~> 0.30"
end
