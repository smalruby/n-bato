# いまの会員・役員の情報を今年度の記録にし(見直し第5回の合意)、法人情報を全年度の記録に写す(判断の記録を参照)。
class FillPersonYearsAndOrganizationYears < ActiveRecord::Migration[8.1]
  def up
    [Person, PersonYear, Organization, OrganizationYear].each(&:reset_column_information)
    today = Date.current
    current = (today.month >= 4) ? today.year : today.year - 1
    Audit.without do
      Person.find_each do |p|
        next if PersonYear.exists?(person_id: p.id)

        PersonYear.create!(person: p, fiscal_year: current, **Person.year_attrs.index_with { p.read_attribute(it) }.symbolize_keys)
      end
      years = select_values("SELECT year FROM fiscal_periods").map(&:to_i).presence || [current]
      Organization.find_each do |o|
        values = Organization.year_attrs.index_with { o.read_attribute(it) }.symbolize_keys
        years.each { |y| OrganizationYear.find_or_create_by!(organization: o, fiscal_year: y) { it.assign_attributes(values) } }
      end
    end
  end

  def down
    execute "DELETE FROM person_years"
    execute "DELETE FROM organization_years"
  end
end
