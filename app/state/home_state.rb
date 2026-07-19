# frozen_string_literal: true

module Pando
  class HomeState < ApplicationState
    attribute :title, :string, default: "Pando"
  end
end
