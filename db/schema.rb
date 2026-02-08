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

ActiveRecord::Schema[8.1].define(version: 2026_02_08_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "agents", id: { type: :string, limit: 32 }, force: :cascade do |t|
    t.string "api_key_digest", null: false
    t.datetime "created_at", null: false
    t.integer "currency", default: 100, null: false
    t.text "description"
    t.integer "energy", default: 100, null: false
    t.integer "food", default: 50, null: false
    t.jsonb "goals", default: [], null: false
    t.string "location_id", limit: 32
    t.string "name", null: false
    t.jsonb "personality_traits", default: [], null: false
    t.integer "stamina", default: 100, null: false
    t.string "status", default: "idle", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key_digest"], name: "index_agents_on_api_key_digest", unique: true
    t.index ["location_id"], name: "index_agents_on_location_id"
    t.index ["name"], name: "index_agents_on_name", unique: true
    t.index ["status"], name: "index_agents_on_status"
  end

  create_table "conversation_messages", id: { type: :string, limit: 32 }, force: :cascade do |t|
    t.string "agent_id", limit: 32, null: false
    t.text "content", null: false
    t.string "conversation_id", limit: 32, null: false
    t.datetime "created_at", null: false
    t.integer "tick", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "tick"], name: "index_conversation_messages_on_conversation_id_and_tick"
  end

  create_table "conversation_participants", id: { type: :string, limit: 32 }, force: :cascade do |t|
    t.string "agent_id", limit: 32, null: false
    t.string "conversation_id", limit: 32, null: false
    t.datetime "created_at", null: false
    t.integer "joined_at_tick", null: false
    t.integer "left_at_tick"
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "agent_id"], name: "idx_conv_participants_on_conv_and_agent", unique: true
  end

  create_table "conversations", id: { type: :string, limit: 32 }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "ended_at_tick"
    t.string "location_id", limit: 32, null: false
    t.integer "started_at_tick", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["started_at_tick"], name: "index_conversations_on_started_at_tick"
    t.index ["status"], name: "index_conversations_on_status"
  end

  create_table "events", id: { type: :string, limit: 32 }, force: :cascade do |t|
    t.string "agent_id", limit: 32
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "location_id", limit: 32
    t.jsonb "payload", default: {}, null: false
    t.integer "tick", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "tick"], name: "index_events_on_agent_id_and_tick"
    t.index ["created_at"], name: "index_events_on_created_at"
    t.index ["event_type", "tick"], name: "index_events_on_event_type_and_tick"
    t.index ["event_type"], name: "index_events_on_event_type"
    t.index ["location_id", "tick"], name: "index_events_on_location_id_and_tick"
    t.index ["tick"], name: "index_events_on_tick"
  end

  create_table "locations", id: { type: :string, limit: 32 }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "location_type", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["location_type"], name: "index_locations_on_location_type"
    t.index ["name"], name: "index_locations_on_name", unique: true
  end

  create_table "memories", id: { type: :string, limit: 32 }, force: :cascade do |t|
    t.string "agent_id", limit: 32, null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.integer "importance", default: 5, null: false
    t.string "location_id", limit: 32
    t.string "memory_type", null: false
    t.jsonb "related_agent_ids", default: [], null: false
    t.tsvector "search_vector"
    t.integer "tick", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "memory_type"], name: "index_memories_on_agent_id_and_memory_type"
    t.index ["agent_id", "tick"], name: "index_memories_on_agent_id_and_tick"
    t.index ["importance"], name: "index_memories_on_importance"
    t.index ["memory_type"], name: "index_memories_on_memory_type"
    t.index ["search_vector"], name: "index_memories_on_search_vector", using: :gin
  end

  create_table "relationships", id: { type: :string, limit: 32 }, force: :cascade do |t|
    t.integer "affection", default: 0, null: false
    t.string "agent_id", limit: 32, null: false
    t.datetime "created_at", null: false
    t.integer "familiarity", default: 0, null: false
    t.integer "last_interaction_tick"
    t.integer "respect", default: 0, null: false
    t.string "target_agent_id", limit: 32, null: false
    t.integer "trust", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "target_agent_id"], name: "index_relationships_on_agent_id_and_target_agent_id", unique: true
    t.index ["target_agent_id"], name: "index_relationships_on_target_agent_id"
  end

  add_foreign_key "agents", "locations"
  add_foreign_key "conversation_messages", "agents"
  add_foreign_key "conversation_messages", "conversations"
  add_foreign_key "conversation_participants", "agents"
  add_foreign_key "conversation_participants", "conversations"
  add_foreign_key "conversations", "locations"
  add_foreign_key "events", "agents"
  add_foreign_key "events", "locations"
  add_foreign_key "memories", "agents"
  add_foreign_key "memories", "locations"
  add_foreign_key "relationships", "agents"
  add_foreign_key "relationships", "agents", column: "target_agent_id"
end
