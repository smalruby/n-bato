require "test_helper"
require Rails.root.join("db/demo/seed").to_s

# 架空のデータの種(bin/demo、issue #14)は、日付をきょうから決める。年度の初め・総会の前・年度の後半のどの日に流しても入ること
class DemoSeedTest < ActiveSupport::TestCase
  [ Date.new(2027, 4, 2), Date.new(2027, 6, 10), Date.new(2026, 11, 24), Date.new(2027, 3, 30) ].each do |day|
    test "#{day} に流しても入り、いまの状態がイベントと合う" do
      travel_to day do
        seed = Demo.seed!(password: "demo-test", today: day)
        assert_equal FiscalYear.for(day).year, seed.year
        assert_equal (seed.year - 3..seed.year).to_a, FiscalPeriod.years
        assert FiscalPeriod.for(seed.year - 3).closed?
        assert User.authenticate_by(email_address: Demo::EMAIL, password: "demo-test")
        assert Resolution.find_by!(body: "general_meeting").established?
        assert_empty ModelVerification.mismatches
      end
    end
  end
end
