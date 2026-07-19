# frozen_string_literal: true

class CreateRoomParticipants < ActiveRecord::Migration[8.1]
  def change
    create_table :room_participants do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :fingerprint, null: false
      t.datetime :joined_at
      t.timestamps
      t.index [:conversation_id, :fingerprint], unique: true
    end

    # Last-writer-wins guard for membership snapshots replayed out of order.
    add_column :conversations, :membership_updated_at, :datetime
  end
end
