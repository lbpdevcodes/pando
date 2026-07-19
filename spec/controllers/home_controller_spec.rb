# frozen_string_literal: true

require "pando"

RSpec.describe Pando::HomeController do
  let(:application) { Pando::Application.new }

  subject(:controller) { described_class.new(application: application) }

  describe "#show" do
    it "renders the view with the state" do
      response = controller.dispatch(:show)

      expect(response).to respond_to(:body)
    end
  end
end
