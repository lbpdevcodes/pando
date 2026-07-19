# frozen_string_literal: true

class CreateContactDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :contact_devices do |t|
      t.string :fingerprint, null: false, index: true
      t.string :mailbox, null: false, index: {unique: true}
      # The device's public encryption key (base64) — public data, kept
      # plaintext so inbound sender lookup is an indexed query, not a scan.
      t.string :box_key, null: false, index: true
      # Full signed bundle JSON (encrypted at rest); nil until the device's
      # announce arrives — such rows resolve the sender but can't be sealed to.
      t.text :bundle
      t.timestamps
    end
  end
end
