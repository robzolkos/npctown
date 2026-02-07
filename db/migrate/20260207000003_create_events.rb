class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events, id: :string, limit: 32 do |t|
      t.string :event_type, null: false
      t.integer :tick, null: false, default: 0
      t.jsonb :payload, null: false, default: {}
      t.string :agent_id, limit: 32
      t.string :location_id, limit: 32

      t.timestamps
    end

    add_index :events, :event_type
    add_index :events, :tick
    add_index :events, [ :event_type, :tick ]
    add_index :events, [ :agent_id, :tick ]
    add_index :events, [ :location_id, :tick ]
    add_index :events, :created_at
    add_foreign_key :events, :agents, column: :agent_id
    add_foreign_key :events, :locations, column: :location_id
  end
end
