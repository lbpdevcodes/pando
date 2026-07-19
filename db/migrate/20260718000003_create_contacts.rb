# frozen_string_literal: true

class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :contacts do |t|
      t.string :fingerprint, null: false, index: {unique: true}
      t.text :name
      t.string :trust_level, null: false, default: "unverified"
      t.timestamps
    end
  end
end
