class CreateOrganizations < ActiveRecord::Migration[8.0]
  def change
    create_table :organizations do |t|
      t.string :name
      t.string :name_en
      t.string :address
      t.string :representative_title
      t.string :representative_name
      t.date :established_on
      t.integer :first_fiscal_year
      t.string :competent_authority
      t.text :accounting_standard_note

      t.timestamps
    end
  end
end
