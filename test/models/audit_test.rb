require "test_helper"

class AuditTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @cash = Account.create!(fiscal_year: 2024, code: 100, name: "現      金")
    @supplies = Account.create!(fiscal_year: 2024, code: 658, name: "消耗品費(事業)")
  end

  def entry_op(&) = Audit.operation(user: @user, scope: "journal_entries", &)

  test "変更を操作として残し、元に戻す・やり直すができる" do
    entry = entry_op { JournalEntry.create!(entry_date: Date.new(2024, 5, 1), debit_account: @supplies, credit_account: @cash, amount: 1000, summary: "文具") }
    entry_op { entry.update!(amount: 1200) }
    assert_equal({undo: 2, redo: 0}, Audit.counts(@user, "journal_entries"))

    Audit.undo!(@user, "journal_entries")
    assert_equal 1000, entry.reload.amount
    assert_equal({undo: 1, redo: 1}, Audit.counts(@user, "journal_entries"))

    Audit.redo!(@user, "journal_entries")
    assert_equal 1200, entry.reload.amount

    Audit.undo!(@user, "journal_entries")
    Audit.undo!(@user, "journal_entries")
    assert_nil JournalEntry.find_by(id: entry.id), "追加を元に戻すと消える"

    Audit.redo!(@user, "journal_entries")
    assert_equal 1000, JournalEntry.find(entry.id).amount, "やり直すと同じ ID で戻る"
    assert_equal %w[do do undo redo undo undo redo], AuditOperation.where(scope: "journal_entries").order(:id).pluck(:kind), "履歴は消さずに増える"
  end

  test "削除を元に戻すと、同じ記録が戻る" do
    entry = JournalEntry.create!(entry_date: Date.new(2024, 5, 1), debit_account: @supplies, credit_account: @cash, amount: 500, summary: "電池")
    entry_op { entry.destroy! }
    Audit.undo!(@user, "journal_entries")
    restored = JournalEntry.find(entry.id)
    assert_equal [500, "電池", Date.new(2024, 5, 1)], [restored.amount, restored.summary, restored.entry_date]
  end

  test "新しい操作をすると、やり直せなくなる" do
    entry = entry_op { JournalEntry.create!(entry_date: Date.new(2024, 5, 1), debit_account: @supplies, credit_account: @cash, amount: 1000) }
    entry_op { entry.update!(summary: "A") }
    Audit.undo!(@user, "journal_entries")
    entry_op { entry.update!(summary: "B") }
    assert_equal 0, Audit.counts(@user, "journal_entries")[:redo]
  end

  test "そのあと別の画面で変わった値は、元に戻さずに知らせる" do
    entry = JournalEntry.create!(entry_date: Date.new(2024, 5, 1), debit_account: @supplies, credit_account: @cash, amount: 1000)
    entry_op { entry.update!(summary: "A") }
    Audit.operation(user: @user, scope: "other") { entry.update!(summary: "B") }
    assert_raises(Audit::Conflict) { Audit.undo!(@user, "journal_entries") }
    assert_equal "B", entry.reload.summary
  end

  test "元に戻せない操作は対象にしない" do
    entry = JournalEntry.create!(entry_date: Date.new(2024, 5, 1), debit_account: @supplies, credit_account: @cash, amount: 1000)
    entry_op do
      Audit.final!("承認して記帳")
      entry.update!(summary: "承認")
    end
    assert_equal 0, Audit.counts(@user, "journal_entries")[:undo]
    assert_equal "final", AuditOperation.last.kind
  end

  test "住所などの暗号化した項目は、履歴でも暗号化して保存する" do
    Audit.operation(user: @user, scope: "people") { Person.create!(name: "山田", address: "松江市テスト町1") }
    raw = AuditChange.connection.select_value("SELECT changeset FROM audit_changes ORDER BY id DESC LIMIT 1")
    assert_not_includes raw, "テスト町"
    assert_equal "松江市テスト町1", AuditChange.last.changeset["address"].last
  end

  test "金額の BigDecimal は文字で残す" do
    assert_equal "1.5", Audit.dump(BigDecimal("1.5"))
    assert_equal "2024-05-01", Audit.dump(Date.new(2024, 5, 1))
    assert_equal 3, Audit.dump(3)
  end

  test "追加を元に戻せない(ほかの記録が使っている)ときは知らせる" do
    account = Audit.operation(user: @user, scope: "accounts") { Account.create!(fiscal_year: 2024, code: 101, name: "小口現金") }
    OpeningBalance.create!(fiscal_year: 2024, account:, amount: 100)
    error = assert_raises(Audit::Conflict) { Audit.undo!(@user, "accounts") }
    assert_match "元に戻せませんでした", error.message
    assert Account.exists?(account.id)
  end

  test "削除をやり直す。やり直せない(ほかの記録が使い始めた)ときは知らせる" do
    a = Account.create!(fiscal_year: 2024, code: 101, name: "小口現金")
    b = Account.create!(fiscal_year: 2024, code: 102, name: "預り金")
    Audit.operation(user: @user, scope: "accounts") { a.destroy! }
    Audit.undo!(@user, "accounts")
    Audit.redo!(@user, "accounts")
    assert_not Account.exists?(a.id), "やり直すと、もう一度消える"

    Audit.operation(user: @user, scope: "accounts") { b.destroy! }
    Audit.undo!(@user, "accounts")
    OpeningBalance.create!(fiscal_year: 2024, account_id: b.id, amount: 100)
    error = assert_raises(Audit::Conflict) { Audit.redo!(@user, "accounts") }
    assert_match "やり直せませんでした", error.message
    assert Account.exists?(b.id)
  end
end
