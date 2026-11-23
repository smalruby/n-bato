namespace :fiscal_periods do
  desc "年度の記録を作る(設立年度から今年度まで)"
  task ensure: :environment do
    FiscalPeriod.ensure!
    FiscalPeriod.ordered.each { puts "#{it.label} #{it.state_label}" }
  end

  desc "UNTIL 年度までを締めた年度として記録する(導入時の初期状態。例: UNTIL=2023)"
  task close_until: :environment do
    until_year = Integer(ENV.fetch("UNTIL"))
    FiscalPeriod.ensure!
    Audit.without do
      FiscalPeriod.where(year: ..until_year, closed_on: nil).find_each do |p|
        p.update!(closed_on: Date.current, closed_at: Time.current, note: "n-bato の導入時に、締めた年度として登録した")
      end
    end
    FiscalPeriod.ordered.each { puts "#{it.label} #{it.state_label}" }
  end
end
