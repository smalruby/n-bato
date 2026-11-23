class CreateProcedures < ActiveRecord::Migration[8.1]
  def change
    # 年に一度の手続き 1 回分(例: 令和7年度分の事業報告書等の提出)。手順の並びは config/procedures/*.yml。
    create_table :procedure_runs do |t|
      t.string :kind, null: false
      t.integer :period, null: false
      t.text :note
      t.timestamps
    end
    add_index :procedure_runs, [ :kind, :period ], unique: true

    create_table :procedure_steps do |t|
      t.references :procedure_run, null: false, foreign_key: true
      t.string :key, null: false
      t.string :status, null: false, default: "open" # open / done / skipped
      t.json :checks, null: false, default: {}         # {確かめたこと: "2026-11-20"}
      t.text :note
      t.date :completed_on
      t.timestamps
    end
    add_index :procedure_steps, [ :procedure_run_id, :key ], unique: true
  end
end
