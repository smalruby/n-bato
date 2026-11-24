module Ledger
  # 1 事業年度の数字。金額は「その科目の通常の向き」をプラスにする
  # (資産・費用は借方、負債・正味財産・収益は貸方)。
  class YearStatement
    attr_reader :fiscal_year, :opening_balances, :entries

    def initialize(fiscal_year, opening_balances, entries)
      @fiscal_year = fiscal_year
      @opening_balances = opening_balances.reject { |_, v| v.zero? }
      @entries = entries
    end

    def year = fiscal_year.year

    # 科目ごとの当期の増減(通常の向きでプラス)
    def movements
      @movements ||= Hash.new(0).tap do |h|
        entries.each do |e|
          h[e.debit_account] += e.debit_account.debit_normal? ? e.amount : -e.amount
          h[e.credit_account] += e.credit_account.debit_normal? ? -e.amount : e.amount
        end
      end
    end

    # 科目 × 部門ごとの当期の増減(活動計算書の科目だけ)
    def activity_by_department
      @activity_by_department ||= Hash.new(0).tap do |h|
        entries.each do |e|
          [[e.debit_account, e.debit_department, :debit], [e.credit_account, e.credit_department, :credit]].each do |account, dept, side|
            next unless account.activity?

            sign = ((side == :debit) == account.debit_normal?) ? 1 : -1
            h[[account, dept]] += sign * e.amount
          end
        end
      end
    end

    def closing_balances
      @closing_balances ||= begin
        accounts = (opening_balances.keys + movements.keys.select(&:balance_sheet?)).uniq
        accounts.to_h { |a| [a, opening_balances.fetch(a, 0) + movements.fetch(a, 0)] }.reject { |_, v| v.zero? }
      end
    end

    def activity_amounts = movements.select { |a, v| a.activity? && !v.zero? }

    def total(category, amounts = activity_amounts) = amounts.sum { |a, v| (a.category == category) ? v : 0 }

    def revenue_total = total("revenue")
    def program_expense_total = total("program_expense")
    def admin_expense_total = total("admin_expense")
    def expense_total = program_expense_total + admin_expense_total
    def ordinary_change = revenue_total - expense_total

    # 経常外は 8xx = 収益、9xx = 費用 とみなす(会計王の科目体系。実データにまだ無い)
    def extraordinary_change
      activity_amounts.sum { |a, v|
        if a.category == "extraordinary"
          (a.code < 900) ? v : -v
        else
          0
        end
      }
    end

    def net_assets_change = ordinary_change + extraordinary_change

    def assets_total(balances) = balances.sum { |a, v| (a.category == "asset") ? v : 0 }
    def liabilities_total(balances) = balances.sum { |a, v| (a.category == "liability") ? v : 0 }

    def opening_net_assets = assets_total(opening_balances) - liabilities_total(opening_balances)
    def closing_assets_total = assets_total(closing_balances)
    def closing_liabilities_total = liabilities_total(closing_balances)
    def closing_net_assets = closing_assets_total - closing_liabilities_total

    # 活動計算書と貸借対照表がつながっているか
    def balanced? = opening_net_assets + net_assets_change == closing_net_assets

    def program_expense_by_department
      activity_by_department.select { |(a, _), v| a.category == "program_expense" && !v.zero? }
        .group_by { |(_, d), _| d }.transform_values { |pairs| pairs.sum(&:last) }
    end
  end
end
