# frozen_string_literal: true

require "pando"

RSpec.describe Pando::Home::ShowView do
  describe "#render" do
    it "renders the state title" do
      view = described_class.new(
        home: double(title: "Pando"),
        theme: Pando::Application.new.theme
      )

      expect(view.render).to include("Pando")
    end
  end
end
