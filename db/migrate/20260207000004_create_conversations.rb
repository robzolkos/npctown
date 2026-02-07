class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations, id: :string, limit: 32 do |t|
      t.string :location_id, limit: 32, null: false
      t.string :status, null: false, default: "active"
      t.integer :started_at_tick, null: false
      t.integer :ended_at_tick

      t.timestamps
    end

    add_index :conversations, :status
    add_index :conversations, :started_at_tick
    add_foreign_key :conversations, :locations, column: :location_id
  end
end
