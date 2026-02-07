class CreateConversationParticipants < ActiveRecord::Migration[8.1]
  def change
    create_table :conversation_participants, id: :string, limit: 32 do |t|
      t.string :conversation_id, limit: 32, null: false
      t.string :agent_id, limit: 32, null: false
      t.integer :joined_at_tick, null: false
      t.integer :left_at_tick

      t.timestamps
    end

    add_index :conversation_participants, [ :conversation_id, :agent_id ], unique: true,
              name: "idx_conv_participants_on_conv_and_agent"
    add_foreign_key :conversation_participants, :conversations, column: :conversation_id
    add_foreign_key :conversation_participants, :agents, column: :agent_id
  end
end
