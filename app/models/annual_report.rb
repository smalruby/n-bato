# 年度の事業報告書(所轄庁へ出す「事業報告書等」の 1 年分)。
class AnnualReport < ApplicationRecord
  DEFAULT_OTHER_BUSINESS = "定款にその他の事業の定めがないため、該当なし。".freeze
  NOT_HELD = "当年度は開催しなかった。".freeze

  has_many :program_activities, -> { order(:position, :department_id) }, dependent: :destroy
  accepts_nested_attributes_for :program_activities

  validates :fiscal_year, presence: true, uniqueness: true

  after_initialize do
    next unless new_record?

    self.other_business = DEFAULT_OTHER_BUSINESS if other_business.blank?
    self.board_meetings = NOT_HELD if board_meetings.blank?
    self.general_meetings = NOT_HELD if general_meetings.blank?
  end

  def fiscal_year_object = FiscalYear.new(fiscal_year)

  # 事業の区分(①〜⑨)すべてについて、行を用意する
  def ensure_program_activities
    Department.in_year(fiscal_year).ordered.where(code: 111..119).each_with_index do |dept, i|
      next if program_activities.any? { it.department_id == dept.id }

      program_activities.build(department: dept, position: i)
    end
    self
  end

  # 前年度の内容を写して、新しい年度の下書きを作る
  def self.draft_for(year)
    report = find_or_initialize_by(fiscal_year: year)
    return report if report.persisted?

    if (prev = find_by(fiscal_year: year - 1))
      report.assign_attributes(prev.attributes.slice("achievements", "other_business", "members_note"))
      prev.program_activities.includes(:department).each do |pa|
        # 部門は年度ごとのデータセット。この年度の同じコードの部門に付け替える
        dept = pa.department.in_year(year) or next
        report.program_activities.build(pa.attributes.slice("content", "schedule", "beneficiaries", "report", "position").merge(department: dept))
      end
    end
    report.ensure_program_activities
  end

  def program_expenses(statement)
    statement.program_expense_by_department.transform_keys { it&.id }
  end

  # 会員数。member_counts に人が入れた数があればそれを使い、無ければ会員の記録から数える。
  def member_count(kind)
    counts = member_counts.presence || {}
    return counts[kind].to_i if counts.key?(kind)

    Membership.in_fiscal_year(fiscal_year).where(kind: kind).count
  end

  def previous_member_count(kind) = AnnualReport.find_by(fiscal_year: fiscal_year - 1)&.member_count(kind) || Membership.in_fiscal_year(fiscal_year - 1).where(kind: kind).count

  def status
    if submitted_on then "submitted"
    elsif approved_on then "approved"
    else "draft"
    end
  end

  def status_label = { "submitted" => "提出済み", "approved" => "総会承認済み", "draft" => "作成中" }[status]
  def due_on = Date.new(fiscal_year + 1, 6, 30)
end
