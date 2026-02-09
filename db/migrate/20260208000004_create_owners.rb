class CreateOwners < ActiveRecord::Migration[8.1]
  def change
    create_table :owners, id: :string, limit: 32 do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :api_key_digest, null: false
      t.string :email_verification_token
      t.datetime :verified_at
      t.integer :agent_limit, null: false, default: 3

      t.timestamps
    end

    add_index :owners, :email, unique: true
    add_index :owners, :api_key_digest, unique: true
    add_index :owners, :email_verification_token, unique: true
  end
end
