module Ledger
  # 帳簿全体。年度初めの残高(OpeningBalance)と仕訳から、各年度の計算書類の数字を作る。
  # ある年度に OpeningBalance が無ければ、前年度末の残高を繰り越す。
  class Book
    def initialize(entries: JournalEntry.active, opening_balances: OpeningBalance.all)
      @entries = entries.includes(:debit_account, :credit_account, :debit_department, :credit_department).to_a
      @openings = opening_balances.includes(:account).group_by(&:fiscal_year)
      @statements = {}
    end

    def years
      first = [ @entries.map(&:fiscal_year).min, @openings.keys.min ].compact.min
      return [] unless first

      last = [ @entries.map(&:fiscal_year).max, FiscalYear.current.year - 1 ].compact.max
      (first..last).to_a
    end

    def statement(year)
      @statements[year] ||= begin
        opening = if @openings[year]
          @openings[year].to_h { |ob| [ ob.account, ob.amount ] }
        elsif years.first && year > years.first
          carry_over(statement(year - 1).closing_balances, year)
        else
          {}
        end
        YearStatement.new(FiscalYear.new(year), opening, @entries.select { |e| e.fiscal_year == year })
      end
    end

    def statements = years.map { |y| statement(y) }

    # 指定日の終わりの残高(貸借対照表の科目)
    def balance_as_of(account, date)
      fy = FiscalYear.for(date).year
      return 0 if years.empty? || fy < years.first

      opening = fy > years.last ? carry_over(statement(years.last).closing_balances, fy) : statement(fy).opening_balances
      opening.sum { |a, v| a.code == account.code ? v : 0 } + statement_entries_until(account, fy, date)
    end

    # 科目の元帳(年度の期首残高と、その科目の仕訳・残高の推移)
    def account_ledger(account, year)
      s = statement(year)
      account = Account.find_by(fiscal_year: year, code: account.code) || account
      balance = s.opening_balances.fetch(account, 0)
      rows = s.entries.select { |e| e.debit_account == account || e.credit_account == account }
                      .sort_by { |e| [ e.entry_date, e.slip_number.to_i, e.line_number, e.id ] }
                      .map do |e|
        debit = e.debit_account == account ? e.amount : 0
        credit = e.credit_account == account ? e.amount : 0
        balance += account.debit_normal? ? debit - credit : credit - debit
        { entry: e, counter: e.debit_account == account ? e.credit_account : e.debit_account, debit:, credit:, balance: }
      end
      { opening: s.opening_balances.fetch(account, 0), rows:, closing: balance }
    end

    private

    # 前の年度の期末残高を、その年度の科目(年度ごとのデータセット)に付け替える。科目はコードで対応させる。
    def carry_over(balances, year)
      accounts = Account.where(fiscal_year: year).index_by(&:code)
      balances.each_with_object(Hash.new(0)) { |(a, v), h| h[accounts[a.code] || a] += v }
    end

    def statement_entries_until(account, year, date)
      @entries.select { |e| e.fiscal_year == year && e.entry_date <= date }.sum do |e|
        sign = account.debit_normal? ? 1 : -1
        (e.debit_account.code == account.code ? sign * e.amount : 0) - (e.credit_account.code == account.code ? sign * e.amount : 0)
      end
    end
  end
end
