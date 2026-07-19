# frozen_string_literal: true

class CreateAttachments < ActiveRecord::Migration[8.1]
  def change
    create_table :attachments do |t|
      t.references :message, foreign_key: true
      # Not unique: our sending row and the peer's receiving row legitimately
      # share the wire id (dedup is per side, scoped through the message's
      # direction in code).
      t.string :attachment_id, null: false, index: true
      t.text :name
      t.string :mime
      t.integer :size, null: false
      t.string :digest, null: false
      t.integer :total_chunks, null: false
      t.integer :received_chunks, null: false, default: 0
      t.integer :acked_chunks, null: false, default: 0
      t.string :status, null: false, default: "sending"
      t.boolean :voice, null: false, default: false
      t.float :duration_s
      t.timestamps
    end

    add_column :messages, :kind, :string, null: false, default: "text"
  end
end
