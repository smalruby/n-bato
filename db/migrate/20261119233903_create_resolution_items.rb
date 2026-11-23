class CreateResolutionItems < ActiveRecord::Migration[8.1]
  def change
    create_table :resolution_items do |t|
      t.references :resolution, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.string :kind, null: false, default: "general" # general / officer_election / annual_report_approval
      t.string :title, null: false
      t.text :content, null: false, default: ""
      t.json :payload
      t.date :applied_on
      t.timestamps
    end
  end
end
