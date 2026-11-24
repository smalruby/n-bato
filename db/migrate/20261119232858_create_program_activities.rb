class CreateProgramActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :program_activities do |t|
      t.references :annual_report, null: false, foreign_key: true
      t.references :department, null: false, foreign_key: true
      t.text :content, null: false, default: ""
      t.text :schedule, null: false, default: ""
      t.text :beneficiaries, null: false, default: ""
      t.text :report, null: false, default: ""
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :program_activities, [:annual_report_id, :department_id], unique: true
  end
end
