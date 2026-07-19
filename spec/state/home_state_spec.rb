# frozen_string_literal: true

require "pando"

RSpec.describe Pando::HomeState do
  describe "#title" do
    it "has the correct default string value" do
      instance = described_class.new
      expect(instance.title).to eq("Pando")
    end

    it "accepts overridden title values" do
      instance = described_class.new(title: "Alternative")
      expect(instance.title).to eq("Alternative")
    end
  end
end
