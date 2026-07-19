# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_19_000008) do
  create_table "attachments", force: :cascade do |t|
    t.integer "acked_chunks", default: 0, null: false
    t.string "attachment_id", null: false
    t.datetime "created_at", null: false
    t.string "digest", null: false
    t.float "duration_s"
    t.integer "message_id"
    t.string "mime"
    t.text "name"
    t.integer "received_chunks", default: 0, null: false
    t.integer "size", null: false
    t.string "status", default: "sending", null: false
    t.integer "total_chunks", null: false
    t.datetime "updated_at", null: false
    t.boolean "voice", default: false, null: false
    t.index ["attachment_id"], name: "index_attachments_on_attachment_id"
    t.index ["message_id"], name: "index_attachments_on_message_id"
  end

  create_table "contact_devices", force: :cascade do |t|
    t.string "box_key", null: false
    t.text "bundle"
    t.datetime "created_at", null: false
    t.string "fingerprint", null: false
    t.string "mailbox", null: false
    t.datetime "updated_at", null: false
    t.index ["box_key"], name: "index_contact_devices_on_box_key"
    t.index ["fingerprint"], name: "index_contact_devices_on_fingerprint"
    t.index ["mailbox"], name: "index_contact_devices_on_mailbox", unique: true
  end

  create_table "contact_requests", force: :cascade do |t|
    t.text "bundle"
    t.string "content_id"
    t.datetime "created_at", null: false
    t.string "direction", null: false
    t.string "fingerprint", null: false
    t.text "greeting"
    t.text "name"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["content_id", "direction"], name: "index_contact_requests_on_content_id_and_direction", unique: true
    t.index ["fingerprint", "direction"], name: "index_contact_requests_on_fingerprint_and_direction", unique: true
  end

  create_table "contacts", force: :cascade do |t|
    t.text "bundle"
    t.datetime "created_at", null: false
    t.string "fingerprint", null: false
    t.text "name"
    t.string "trust_level", default: "unverified", null: false
    t.datetime "updated_at", null: false
    t.index ["fingerprint"], name: "index_contacts_on_fingerprint", unique: true
  end

  create_table "conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "kind", default: "dm", null: false
    t.datetime "last_activity_at"
    t.datetime "membership_updated_at"
    t.text "title"
    t.integer "ttl", default: 0, null: false
    t.integer "unread_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_conversations_on_key", unique: true
  end

  create_table "messages", force: :cascade do |t|
    t.text "body"
    t.string "content_id"
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "direction", null: false
    t.datetime "expires_at"
    t.string "kind", default: "text", null: false
    t.string "sender_fingerprint"
    t.datetime "sent_at", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["content_id", "direction"], name: "index_messages_on_content_id_and_direction", unique: true
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["expires_at"], name: "index_messages_on_expires_at"
  end

  create_table "relay_configs", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.string "name"
    t.text "token"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["url"], name: "index_relay_configs_on_url", unique: true
  end

  create_table "room_participants", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "fingerprint", null: false
    t.datetime "joined_at"
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "fingerprint"], name: "index_room_participants_on_conversation_id_and_fingerprint", unique: true
    t.index ["conversation_id"], name: "index_room_participants_on_conversation_id"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  add_foreign_key "attachments", "messages"
  add_foreign_key "messages", "conversations"
  add_foreign_key "room_participants", "conversations"
end
