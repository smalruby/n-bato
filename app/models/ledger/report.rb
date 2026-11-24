module Ledger
  # 計算書類(活動計算書・貸借対照表・財産目録)の行を作る。
  # 行: Line(label, amount, level, strong)。amount が nil の行は見出し。
  class Report
    Line = Data.define(:label, :amount, :level, :strong) do
      def heading? = amount.nil?
    end

    KINDS = {
      "activity" => "活動計算書", "balance_sheet" => "貸借対照表",
      "inventory" => "財産目録", "notes" => "計算書類の注記"
    }.freeze

    attr_reader :statement

    def initialize(statement) = @statement = statement

    def activity
      s = statement
      amounts = s.activity_amounts
      lines = [heading("Ⅰ　経常収益", 0)]
      Account::REVENUE_GROUPS.map(&:last).uniq.each_with_index do |group, i|
        accounts = amounts.select { |a, _| a.category == "revenue" && a.activity_group == group }
        lines << line("#{i + 1}　#{group}", accounts.sum(&:last), 1)
        accounts.sort_by { |a, _| a.code }.each { |a, v| lines << line(a.display_name, v, 2) }
      end
      lines << line("経常収益計", s.revenue_total, 0, true)
      lines << heading("Ⅱ　経常費用", 0)
      [["program_expense", "１　事業費", "事業費計"], ["admin_expense", "２　管理費", "管理費計"]].each do |category, title, total_label|
        lines << heading(title, 1)
        ["人件費", "その他経費"].each_with_index do |group, i|
          accounts = amounts.select { |a, _| a.category == category && a.activity_group == group }
          lines << heading("（#{i + 1}）#{group}", 2)
          accounts.sort_by { |a, _| a.code }.each { |a, v| lines << line(a.display_name, v, 3) }
          lines << line("#{group}計", accounts.sum(&:last), 3)
        end
        lines << line(total_label, s.total(category), 2)
      end
      lines << line("経常費用計", s.expense_total, 0, true)
      lines << line("当期経常増減額", s.ordinary_change, 0, true)
      %w[経常外収益 経常外費用].each_with_index do |group, i|
        accounts = amounts.select { |a, _| a.activity_group == group }
        lines << heading("#{%w[Ⅲ Ⅳ][i]}　#{group}", 0)
        accounts.sort_by { |a, _| a.code }.each { |a, v| lines << line(a.display_name, v, 2) }
        lines << line("#{group}計", accounts.sum(&:last), 1)
      end
      lines << line("税引前当期正味財産増減額", s.net_assets_change, 0, true)
      lines << line("当期正味財産増減額", s.net_assets_change, 0, true)
      lines << line("前期繰越正味財産額", s.opening_net_assets, 0)
      lines << line("次期繰越正味財産額", s.opening_net_assets + s.net_assets_change, 0, true)
    end

    def balance_sheet
      s = statement
      lines = bs_assets_and_liabilities
      lines << heading("Ⅲ　正味財産の部", 0)
      lines << line("前期繰越正味財産", s.opening_net_assets, 1)
      lines << line("当期正味財産増減額", s.net_assets_change, 1)
      lines << line("正味財産合計", s.closing_net_assets, 0, true)
      lines << line("負債及び正味財産合計", s.closing_liabilities_total + s.closing_net_assets, 0, true)
    end

    def inventory
      bs_assets_and_liabilities << line("正味財産", statement.closing_net_assets, 0, true)
    end

    # 事業費の内訳(部門 × 科目)
    def program_expense_breakdown
      statement.activity_by_department
        .select { |(a, _), v| a.category == "program_expense" && !v.zero? }
        .group_by { |(_, d), _| d }
        .sort_by { |d, _| d&.code || 0 }
        .map { |d, pairs| [d, pairs.map { |(a, _), v| [a, v] }.sort_by { |a, _| a.code }] }
    end

    private

    def bs_assets_and_liabilities
      balances = statement.closing_balances
      lines = [heading("Ⅰ　資産の部", 0)]
      lines += section(balances, "asset", [["１　流動資産", "流動資産合計", :current_asset?], ["２　固定資産", "固定資産合計", nil]])
      lines << line("資産合計", statement.closing_assets_total, 0, true)
      lines << heading("Ⅱ　負債の部", 0)
      lines += section(balances, "liability", [["１　流動負債", "流動負債合計", :current_liability?], ["２　固定負債", "固定負債合計", nil]])
      lines << line("負債合計", statement.closing_liabilities_total, 0, true)
    end

    def section(balances, category, parts)
      items = balances.select { |a, _| a.category == category }.sort_by { |a, _| a.code }
      current = items.select { |a, _| a.public_send(parts[0][2]) }
      fixed = items - current
      [[parts[0], current], [parts[1], fixed]].flat_map do |(title, total_label, _), accounts|
        [heading(title, 1)] + accounts.map { |a, v| line(a.display_name, v, 2) } + [line(total_label, accounts.sum(&:last), 2)]
      end
    end

    def heading(label, level) = Line.new(label, nil, level, level.zero?)
    def line(label, amount, level, strong = false) = Line.new(label, amount, level, strong)
  end
end
