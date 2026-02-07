class CreateConversationMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :conversation_messages, id: :string, limit: 32 do |t|
      t.string :conversation_id, limit: 32, null: false
      t.string :agent_id, limit: 32, null: false
      t.text :content, null: false
      t.integer :tick, null: false

      t.timestamps
    end

    add_index :conversation_messages, [ :conversation_id, :tick ]
    add_foreign_key :conversation_messages, :conversations, column: :conversation_id
    add_foreign_key :conversation_messages, :agents, column: :agent_id
  end
end
