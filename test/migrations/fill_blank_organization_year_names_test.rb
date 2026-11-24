require "test_helper"
require Rails.root.join("db/migrate/20261124230000_fill_blank_organization_year_names")

# 名前が空の年度の記録(OrganizationYear の名前を必須にする前に保存できたもの)を、法人の名前で埋める
class FillBlankOrganizationYearNamesTest < ActiveSupport::TestCase
  def migrate(verbose: false) = FillBlankOrganizationYearNames.new.tap { it.verbose = verbose }.up

  test "空(nil・空文字・空白だけ)の名前を法人の名前で埋め、ほかの年度はそのまま。2 回流しても同じ" do
    org = Organization.create!(name: "テスト法人", first_fiscal_year: 2023)
    blank_nil = org.organization_years.sole.tap { it.update_column(:name, nil) }
    blank_str = org.organization_years.create!(fiscal_year: 2020, name: "x").tap { it.update_column(:name, "") }
    blank_sp = org.organization_years.create!(fiscal_year: 2019, name: "x").tap { it.update_column(:name, "　") }
    named = org.organization_years.create!(fiscal_year: 2018, name: "旧名の法人")

    assert_no_difference -> { AuditOperation.count } do
      migrate
      migrate
    end
    [blank_nil, blank_str, blank_sp].each { assert_equal "テスト法人", it.reload.name }
    assert_equal "旧名の法人", named.reload.name
    assert blank_str.reload.update(phone: "000-0000-0000"), "埋めたあとは、ほかの項目を直せる"
  end

  test "法人の名前も空なら、その記録は残して知らせる" do
    org = Organization.create!(name: "テスト法人", first_fiscal_year: 2024)
    org.update_column(:name, "")
    record = org.organization_years.sole.tap { it.update_column(:name, nil) }

    assert_output(/法人の名前も空/) { migrate(verbose: true) }
    assert_nil record.reload.name
  end
end
