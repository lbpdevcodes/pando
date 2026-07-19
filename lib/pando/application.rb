# frozen_string_literal: true

module Pando
  class Application < Charming::Application
    root File.expand_path("../..", __dir__)

    Charming::UI::Theme.built_in_names.each do |theme_name|
      theme theme_name.to_sym, built_in: theme_name
    end

    default_theme :phosphor

    def initialize
      super
      saved = Settings.load["theme"]
      session[:theme] ||= saved.to_sym if saved
    end

    def use_theme(name)
      super
      Settings.save(theme: name)
    end
  end
end
