# 年度の事業報告書(所轄庁へ出す「事業報告書等」の 1 年分)。
# 長いイベント(docs/adr/0038)。承認・提出・公告・出し直しが要る・出し直した の日付は、詳細のイベント AnnualReport::Milestone。
# approved_on・submitted_on・bs_published_on・resubmit_needed_on・resubmitted_on は「いまの状態」で、
# AnnualReport::Milestone.record! だけが書き換える(照合は model:verify)。事業の成果・会員数・提出書の日付などの中身は、ふつうに直してよい。
class AnnualReport < ApplicationRecord
  DEFAULT_OTHER_BUSINESS = "定款にその他の事業の定めがないため、該当なし。".freeze
  NOT_HELD = "当年度は開催しなかった。".freeze
  STATE_COLUMNS = AnnualReport::Milestone::KINDS.values.map(&:first).freeze
  # 事業報告の画面で入れる日付(手続きの記録の欄)
  FORM_DATE_COLUMNS = %w[approved_on submitted_on bs_published_on].freeze
  # 決まりで付ける「出し直しが要る」の操作の範囲(FiscalPeriod.changed_after_close!)。事業報告の画面の元に戻すでは戻さない
  AUTO_SCOPE = "annual_reports_auto"

  has_many :program_activities, -> { order(:position, :department_id) }, dependent: :destroy
  has_many :milestones, -> { order(:id) }, class_name: "AnnualReport::Milestone", dependent: :restrict_with_error
  accepts_nested_attributes_for :program_activities

  validates :fiscal_year, presence: true, uniqueness: true
  validate :state_written_by_milestone

  def self.model_name_label = "事業報告"

  # 元に戻す・やり直すのあとに、状態を確かめる事業報告(Audit.check_states!)
  def self.audit_state_owner(change) = find_by(id: change.auditable_id)

  # いまの状態は、節目の種類ごとに最後の記録の日付(docs/adr/0005)
  def derived_state
    latest = milestones.group_by(&:kind).transform_values { it.max_by(&:id) }
    AnnualReport::Milestone::KINDS.to_h { |kind, (column, _)| [ column, latest[kind]&.dated_on ] }
  end

  def state_mismatches
    want = derived_state
    STATE_COLUMNS.reject { Audit.dump(self[it]).to_s == Audit.dump(want[it]).to_s }
  end

  # いまの状態の列を書き換える。呼ぶのは AnnualReport::Milestone.record! だけ。
  def apply_state!(state)
    @applying_state = true
    update!(state)
  ensure
    @applying_state = false
  end

  # 事業報告の画面の保存: 中身を保存し、日付の欄(dates。FORM_DATE_COLUMNS)が変わっていれば節目を記録する。
  # opened: 画面を開いたときの日付(隠した欄 opened_dates)。渡したときは、開いたときから変えた欄だけ記録する。
  # 開いている間に別の操作(手続き・決議の反映)が日付を変えていたら、上書きも消しもせず、何も保存しない(false)。
  # 保存できなければ false(画面に戻すときのために、入れた日付は記録に書かずに持っておく)。
  def save_with_dates(dates, opened: nil)
    dates = dates.to_h.slice(*FORM_DATE_COLUMNS)
    stored = FORM_DATE_COLUMNS.to_h { [ it, self[it] ] }
    opened = opened&.to_h&.slice(*FORM_DATE_COLUMNS)&.transform_values { cast_date(it) }
    dates = dates.reject { |column, on| opened&.key?(column) && cast_date(on) == opened[column] }
    @opened_dates = stored.merge(opened || {})
    if (stale = dates_changed_since_opened(dates, opened, stored)).any?
      dates.except(*stale).each { |column, on| self[column] = on }
      return false
    end

    saved = transaction(requires_new: true) do
      next false unless save

      dates.each { |column, on| AnnualReport::Milestone.record!(self, AnnualReport::Milestone.kind_for(column), on:) }
      true
    end
    dates.each { |column, on| self[column] = on } unless saved
    saved
  end

  # 画面の隠した欄に出す、開いたときの日付(保存できずに画面に戻すときは、入れた日付ではなく開いたときの日付)
  def opened_date(column) = (@opened_dates || {}).fetch(column) { self[column] }

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
      prev.program_activities.includes(:department).each do |pa| # standard:disable Rails/FindEach -- 並び(position)のまま写すため。find_each は並びを無視する
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

  private

  def cast_date(value) = ActiveModel::Type::Date.new.cast(value)

  # 開いたときから変えた欄のうち、いまの日付が開いたときと違うもの。欄はいまの日付にして知らせる(入れた日付は捨てる)
  def dates_changed_since_opened(dates, opened, stored)
    return [] unless opened

    stale = dates.keys.select { opened.key?(it) && stored[it] != opened[it] }
    stale.each do |column|
      on = stored[column]
      name = AnnualReport::Milestone::KINDS.fetch(AnnualReport::Milestone.kind_for(column)).last
      errors.add(:base, "#{name}は、この画面を開いたあとに別の操作で #{on ? on.strftime('%Y/%m/%d') : '空'} に変わっています。" \
                        "欄を新しい日付にしたので、確かめてから保存し直してください")
      @opened_dates[column] = on
    end
    stale
  end

  def state_written_by_milestone
    return if @applying_state

    if new_record?
      errors.add(:base, "事業報告は日付なしで作ってください(日付は AnnualReport::Milestone.record!)") if STATE_COLUMNS.any? { self[it].present? }
    elsif (changed = STATE_COLUMNS & changed_attribute_names_to_save).any?
      errors.add(:base, "#{changed.join('・')} は直接書き換えません。AnnualReport::Milestone.record!(事業報告, 種類, on: …) を使ってください")
    end
  end
end
