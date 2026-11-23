# これまでの変更に年度を付ける(変更の記録の画面で年度ごとに並べるため)
class BackfillAuditChangeFiscalYears < ActiveRecord::Migration[8.1]
  def up
    AuditChange.reset_column_information
    AuditChange.where(fiscal_year: nil).find_each do |c|
      rec = c.record
      year = rec&.send(:audit_fiscal_year)
      year ||= c.snapshot.is_a?(Hash) ? c.snapshot["fiscal_year"]&.to_i : nil
      c.update_column(:fiscal_year, year) if year
    end
  end

  def down; end
end
