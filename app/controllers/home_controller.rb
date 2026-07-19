# frozen_string_literal: true

module Pando
  class HomeController < ApplicationController

    def show
      render :show, home: home, palette: command_palette
    end

    private

    def home
      state(:home, HomeState)
    end
  end
end
