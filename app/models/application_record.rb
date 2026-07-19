# frozen_string_literal: true

ActiveRecord::Type.register(:pando_encrypted, Pando::Store::EncryptedType)

module Pando
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
