class CreateAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :agents, id: :string, limit: 32 do |t|
      t.string :name, null: false
      t.text :description
      t.jsonb :personality_traits, null: false, default: []
      t.jsonb :goals, null: false, default: []
      t.string :location_id, limit: 32
      t.string :status, null: false, default: "idle"
      t.integer :stamina, null: false, default: 100
      t.integer :food, null: false, default: 50
      t.integer :energy, null: false, default: 100
      t.integer :currency, null: false, default: 100
      t.string :api_key_digest, null: false

      t.timestamps
    end

    add_index :agents, :name, unique: true
    add_index :agents, :api_key_digest, unique: true
    add_index :agents, :status
    add_index :agents, :location_id
    add_foreign_key :agents, :locations, column: :location_id
  end
end
