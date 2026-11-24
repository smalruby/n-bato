# 法人の年度の記録(organization_years)の名前を必須にした(以前は空で保存できた)。
# 空の名前が残っていると、次の年度を始める・ほかの項目を直すが保存できないので、法人の名前で埋める。
# - 埋めるのは名前が空(nil・空文字・空白だけ)の行だけ。何度流しても同じ(埋めた行はもう空でない)。
# - 法人の名前も空なら、その行は残して知らせる(人が法人情報の画面で直す)。
# - モデルを通さず SQL で直す(検証・コールバック・操作履歴を通さない。データの写しの直しで、人の操作ではない)。
class FillBlankOrganizationYearNames < ActiveRecord::Migration[8.1]
  def up
    rows = select_rows(<<~SQL)
      SELECT organization_years.id, organization_years.fiscal_year, organization_years.name, organizations.id, organizations.name
      FROM organization_years JOIN organizations ON organizations.id = organization_years.organization_id
    SQL
    rows.each do |id, fiscal_year, name, org_id, org_name|
      next if name.present?

      if org_name.blank?
        say "法人(id=#{org_id})の #{fiscal_year} 年度の記録は名前が空ですが、法人の名前も空なので埋めませんでした。法人情報の画面で直してください"
        next
      end
      execute ActiveRecord::Base.sanitize_sql_array([ "UPDATE organization_years SET name = ? WHERE id = ?", org_name, id ])
    end
  end

  def down
    # 埋めた名前は戻さない(空の名前は、もう保存できない値のため)
  end
end
