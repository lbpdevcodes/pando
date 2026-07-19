# frozen_string_literal: true

class AddBundleToContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :contacts, :bundle, :text
  end
end
