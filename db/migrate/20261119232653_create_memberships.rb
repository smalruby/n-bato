class CreateMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :memberships do |t|
      t.references :person, null: false, foreign_key: true
      t.integer :fiscal_year, null: false
      t.string :kind, null: false, default: "regular"
      t.date :joined_on
      t.integer :fee_amount
      t.date :fee_paid_on
      t.timestamps
    end
    add_index :memberships, [:fiscal_year, :person_id, :kind], unique: true
  end
end
