# 会員の住所の変更・改姓を、日付つきの出来事(イベント)として持つ(見直し第20回、docs/adr/0029)。
# - 人(people)の氏名・よみ・住所は「記録の始まり」の値にする(いちばん古い年度の記録)。
# - それより後の年度で住所・氏名が違っていたら、その年度の中で変わった出来事にする(日は分からないので精度は fiscal_year)。
# - 年度ごとの記録(person_years)からは、氏名・よみ・住所を外す(メール・電話・メモは年度ごとのまま)。
class CreatePersonChangeEvents < ActiveRecord::Migration[8.1]
  class PersonRow < ActiveRecord::Base
    self.table_name = "people"
    encrypts :address, :email, :phone
  end

  class PersonYearRow < ActiveRecord::Base
    self.table_name = "person_years"
    encrypts :address, :email, :phone
  end

  class AddressRow < ActiveRecord::Base
    self.table_name = "person_address_changes"
    encrypts :address
  end

  class NameRow < ActiveRecord::Base
    self.table_name = "person_name_changes"
  end

  def up
    create_table :person_address_changes do |t|
      t.references :person, null: false, foreign_key: true
      t.text :address
      t.date :moved_on, null: false
      t.string :date_precision, null: false, default: "day"
      t.references :recorded_by, foreign_key: { to_table: :users }
      t.text :note, null: false, default: ""
    end
    create_table :person_name_changes do |t|
      t.references :person, null: false, foreign_key: true
      t.string :name, null: false
      t.string :name_kana, null: false, default: ""
      t.string :former_name, null: false, default: ""
      t.boolean :show_former_name, null: false, default: false
      t.date :changed_on, null: false
      t.string :date_precision, null: false, default: "day"
      t.references :recorded_by, foreign_key: { to_table: :users }
      t.text :note, null: false, default: ""
    end
    create_table :person_change_cancellations do |t|
      t.references :change, polymorphic: true, null: false, index: { unique: true }
      t.references :canceller, foreign_key: { to_table: :users }
      t.text :reason, null: false
      t.datetime :cancelled_at, null: false
    end

    PersonRow.reset_column_information
    PersonYearRow.reset_column_information
    PersonRow.find_each do |person|
      years = PersonYearRow.where(person_id: person.id).order(:fiscal_year).to_a
      next if years.empty?

      first = years.first
      person.update_columns(name: first.name, name_kana: first.name_kana, address: first.address)
      years.each_cons(2) do |prev, cur|
        starts = Date.new(cur.fiscal_year, 4, 1)
        if cur.address.to_s != prev.address.to_s
          AddressRow.create!(person_id: person.id, address: cur.address, moved_on: starts, date_precision: "fiscal_year",
                             note: "年度ごとの記録から移した(#{cur.fiscal_year}年度の記録で変わっていた)")
        end
        if cur.name.to_s != prev.name.to_s || cur.name_kana.to_s != prev.name_kana.to_s
          NameRow.create!(person_id: person.id, name: cur.name, name_kana: cur.name_kana, former_name: prev.name.to_s, changed_on: starts,
                          date_precision: "fiscal_year", note: "年度ごとの記録から移した(#{cur.fiscal_year}年度の記録で変わっていた)")
        end
      end
    end

    remove_column :person_years, :name
    remove_column :person_years, :name_kana
    remove_column :person_years, :address
  end

  def down
    add_column :person_years, :name, :string
    add_column :person_years, :name_kana, :string, default: "", null: false
    add_column :person_years, :address, :text
    PersonYearRow.reset_column_information
    PersonRow.find_each do |person|
      PersonYearRow.where(person_id: person.id).find_each do |y|
        y.update_columns(name: person.name, name_kana: person.name_kana, address: person.address)
      end
    end
    change_column_null :person_years, :name, false
    drop_table :person_change_cancellations
    drop_table :person_name_changes
    drop_table :person_address_changes
  end
end
