# 会員・役員・法人情報の年度ごとの記録(デザインシステム「年度」: 年度ごとのデータセット)。
# 人と法人の ID はそのままにし、年度ごとに変わる項目を年度の記録に持つ。
class CreatePersonYearsAndOrganizationYears < ActiveRecord::Migration[8.1]
  def change
    create_table :person_years do |t|
      t.references :person, null: false, foreign_key: true
      t.integer :fiscal_year, null: false
      t.string :name, null: false
      t.string :name_kana, null: false, default: ""
      t.text :address
      t.text :email
      t.text :phone
      t.text :notes, null: false, default: ""
      t.timestamps
    end
    add_index :person_years, %i[person_id fiscal_year], unique: true

    create_table :organization_years do |t|
      t.references :organization, null: false, foreign_key: true
      t.integer :fiscal_year, null: false
      t.string :name
      t.string :name_en
      t.string :address
      t.string :representative_title
      t.string :representative_name
      t.string :phone
      t.string :competent_authority
      t.text :accounting_standard_note
      t.timestamps
    end
    add_index :organization_years, %i[organization_id fiscal_year], unique: true
  end
end
