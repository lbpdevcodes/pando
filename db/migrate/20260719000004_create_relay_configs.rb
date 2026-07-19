# frozen_string_literal: true

class CreateRelayConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :relay_configs do |t|
      t.string :name
      t.string :url, null: false, index: {unique: true}
      t.text :token
      t.boolean :active, null: false, default: false
      t.timestamps
    end
  end
end
