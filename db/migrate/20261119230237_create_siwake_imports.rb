class CreateSiwakeImports < ActiveRecord::Migration[8.0]
  def change
    create_table :siwake_imports do |t|
      t.string :filename, null: false
      t.string :sha256, null: false
      t.string :format_name
      t.string :format_version
      t.string :app_name
      t.string :app_version
      t.datetime :exported_at
      t.string :header_line, null: false
      t.string :columns_line, null: false
      t.integer :entries_count, null: false, default: 0
      t.timestamps
    end
    add_index :siwake_imports, :sha256, unique: true
  end
end
