require "test_helper"

class Compliance::ChecklistTest < ActiveSupport::TestCase
  setup do
    @org = Organization.create!(name: "テスト", first_fiscal_year: 2024)
    @person = Person.create!(name: "役員A")
  end

  test "提出・総会・役員の改選・登記の期限" do
    OfficerTerm.create!(person: @person, role: "chair", starts_on: Date.new(2022, 7, 1), ends_on: Date.new(2024, 6, 30))
    create_annual_report!(2024, submitted_on: Date.new(2025, 6, 1), approved_on: Date.new(2025, 5, 30))
    items = Compliance::Checklist.new(today: Date.new(2026, 11, 20), organization: @org).items
    by_title = items.index_by(&:title)
    assert by_title["2024年度の事業報告書等を所轄庁に提出"].done?
    assert by_title["2025年度の事業報告書等を所轄庁に提出"].overdue?
    assert by_title["2024年度の貸借対照表を公告"].overdue?
    assert items.any? { it.category == "役員" && it.overdue? }
    assert items.any? { it.category == "登記" && it.overdue? }
    assert by_title["2025年度の通常総会（前年度の事業報告・決算の承認）"].overdue?
  end

  test "期限まで 90 日以内は近い、それより先は未完了" do
    OfficerTerm.create!(person: @person, role: "chair", starts_on: Date.new(2025, 1, 1), ends_on: Date.new(2026, 12, 31))
    Registration.create!(kind: "representative_change", cause_on: Date.new(2026, 3, 1), due_on: Date.new(2026, 12, 31), note: "期限の先の登記")
    items = Compliance::Checklist.new(today: Date.new(2026, 4, 10), organization: @org).items
    by_title = items.index_by(&:title)
    assert_equal :upcoming, by_title["2026年度の通常総会（前年度の事業報告・決算の承認）"].status
    assert_equal :open, items.find { it.category == "登記" && it.title.end_with?("期限の先の登記") }.status
    assert_not items.any? { it.category == "役員" }, "任期満了まで 90 日より先"

    soon = Compliance::Checklist.new(today: Date.new(2026, 11, 1), organization: @org).items.find { it.category == "役員" }
    assert_equal :upcoming, soon.status
    assert_equal Date.new(2026, 12, 31), soon.due_on
  end
end
