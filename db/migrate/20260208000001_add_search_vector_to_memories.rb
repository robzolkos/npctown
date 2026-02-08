class AddSearchVectorToMemories < ActiveRecord::Migration[8.0]
  def up
    add_column :memories, :search_vector, :tsvector
    add_index :memories, :search_vector, using: :gin

    # Backfill existing records
    execute <<-SQL
      UPDATE memories SET search_vector = to_tsvector('english', content);
    SQL

    # Auto-populate search_vector on insert/update
    execute <<-SQL
      CREATE TRIGGER memories_search_vector_update
      BEFORE INSERT OR UPDATE OF content ON memories
      FOR EACH ROW EXECUTE FUNCTION
        tsvector_update_trigger(search_vector, 'pg_catalog.english', content);
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS memories_search_vector_update ON memories;"
    remove_column :memories, :search_vector
  end
end
