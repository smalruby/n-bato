# 科目と部門を年度ごとのデータセットにする(デザインシステム「年度」)。
# いまの行を最初の年度に置き、ほかの年度には写しを作って、仕訳・期首の残高・残高確認・AI の提案・事業の実施状況を
# その年度の写しへ付け替える。計算書類の数字は変わらない。
class AddFiscalYearToAccountsAndDepartments < ActiveRecord::Migration[8.1]
  class Acct < ActiveRecord::Base; self.table_name = "accounts"; end
  class Dept < ActiveRecord::Base; self.table_name = "departments"; end

  def up
    add_column :accounts, :fiscal_year, :integer
    add_column :departments, :fiscal_year, :integer
    remove_index :accounts, :code
    remove_index :departments, :code

    years = select_values("SELECT year FROM fiscal_periods ORDER BY year").map(&:to_i)
    if years.empty?
      first = [select_value("SELECT MIN(first_fiscal_year) FROM organizations"), select_value("SELECT MIN(fiscal_year) FROM journal_entries")].compact.map(&:to_i).min
      today = Date.current
      current = (today.month >= 4) ? today.year : today.year - 1
      years = first ? (first..current).to_a : [current]
    end
    first_year = years.first

    Acct.reset_column_information
    Dept.reset_column_information
    Acct.update_all(fiscal_year: first_year)
    Dept.update_all(fiscal_year: first_year)

    acct_map = {first_year => Acct.where(fiscal_year: first_year).to_h { [it.code, it.id] }}
    dept_map = {first_year => Dept.where(fiscal_year: first_year).to_h { [it.code, it.id] }}
    base_accts = Acct.where(fiscal_year: first_year).to_a
    base_depts = Dept.where(fiscal_year: first_year).to_a
    years.drop(1).each do |y|
      acct_map[y] = base_accts.to_h { |a| [a.code, Acct.create!(a.attributes.except("id", "created_at", "updated_at").merge("fiscal_year" => y)).id] }
      dept_map[y] = base_depts.to_h { |d| [d.code, Dept.create!(d.attributes.except("id", "created_at", "updated_at").merge("fiscal_year" => y)).id] }
    end
    code_of_acct = base_accts.to_h { [it.id, it.code] }
    code_of_dept = base_depts.to_h { [it.id, it.code] }

    remap = lambda do |table, year_sql, acct_cols, dept_cols|
      select_rows("SELECT id, #{year_sql}, #{(acct_cols + dept_cols).join(", ")} FROM #{table}").each do |id, year, *refs|
        year = year.to_i.clamp(years.first, years.last)
        sets = []
        acct_cols.each_with_index do |col, i|
          old = refs[i] or next
          new_id = acct_map.dig(year, code_of_acct[old.to_i]) or next
          sets << "#{col} = #{new_id.to_i}" unless new_id == old.to_i
        end
        dept_cols.each_with_index do |col, i|
          old = refs[acct_cols.size + i] or next
          new_id = dept_map.dig(year, code_of_dept[old.to_i]) or next
          sets << "#{col} = #{new_id.to_i}" unless new_id == old.to_i
        end
        execute("UPDATE #{table} SET #{sets.join(", ")} WHERE id = #{id.to_i}") if sets.any?
      end
    end
    fy = ->(date_col) { "CASE WHEN CAST(strftime('%m', #{date_col}) AS INTEGER) >= 4 THEN CAST(strftime('%Y', #{date_col}) AS INTEGER) ELSE CAST(strftime('%Y', #{date_col}) AS INTEGER) - 1 END" }
    remap.call("journal_entries", "fiscal_year", %w[debit_account_id credit_account_id], %w[debit_department_id credit_department_id])
    remap.call("journal_proposals", fy.call("entry_date"), %w[debit_account_id credit_account_id], %w[debit_department_id credit_department_id])
    remap.call("opening_balances", "fiscal_year", %w[account_id], [])
    remap.call("balance_checks", "COALESCE(#{fy.call("checked_on")}, #{years.last})", %w[account_id], [])
    remap.call("program_activities", "(SELECT fiscal_year FROM annual_reports WHERE annual_reports.id = program_activities.annual_report_id)", [], %w[department_id])

    change_column_null :accounts, :fiscal_year, false
    change_column_null :departments, :fiscal_year, false
    add_index :accounts, %i[fiscal_year code], unique: true
    add_index :departments, %i[fiscal_year code], unique: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
