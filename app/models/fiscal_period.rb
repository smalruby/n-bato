# 年度の状態(デザインシステム「年度」)。
# - 締めた(closed_on あり): 直すには理由を書く。
# - 締める前: ふつうに直せる。
# - 仮: 前の年度を締める前の次の年度。仕訳は入れられるが、期首の残高などは前の年度を締めると決まる。
class FiscalPeriod < ApplicationRecord
  belongs_to :closed_by, class_name: "User", optional: true
  validates :year, presence: true, uniqueness: true

  scope :ordered, -> { order(:year) }

  # 年度の記録を用意する。はじめて使うときは設立年度から今年度まで作る。
  # そのあとは、記録のある最後の年度より先は作らない(次の年度は「次の年度を始める」で作る)。
  # 古いデータを取り込んだときは、その年度までさかのぼって作る。
  def self.ensure!
    first = [Organization.first&.first_fiscal_year, JournalEntry.minimum(:fiscal_year), Account.minimum(:fiscal_year)].compact.min || FiscalYear.current.year
    existing = pluck(:year)
    last = existing.max || FiscalYear.current.year
    (first..last).each { |y| existing.include?(y) ? next : create!(year: y) }
    ordered.each(&:ensure_dataset!)
  end

  def self.latest = ordered.last
  def self.next_year = (maximum(:year) || FiscalYear.current.year - 1) + 1

  # 次の年度を始める(会計王の次年度更新と同じ)。前の年度のデータセットを写す。
  def self.start_next!(by: Current.user)
    transaction do
      prev = latest
      period = create!(year: next_year, note: "#{Date.current} に#{by&.name.presence || "人"}が始めた")
      period.ensure_dataset!
      Person.includes(:person_years).find_each do |person|
        source = prev && person.record_for(prev.year)
        person.person_years.create!(source.slice(*Person.year_attrs).merge("fiscal_year" => period.year)) if source
      end
      Organization.includes(:organization_years).find_each do |org|
        source = prev && org.at(prev.year)
        org.organization_years.create!(source.slice(*Organization.year_attrs).merge("fiscal_year" => period.year)) if source
      end
      period
    end
  end

  # 年度を締める。締めたときのデータがその年度の正。次の年度の期首の残高を、この年度の期末の残高で作り直す。
  def close!(by: Current.user, on: Date.current)
    raise ArgumentError, "#{previous.label}を先に締めてください" if previous && !previous.closed?

    transaction do
      update!(closed_on: on, closed_by: by, closed_at: Time.current)
      rebuild_next_opening_balances!
    end
  end

  # 締めを解けないときの理由(BlockedReason)。解ける・締めていないなら nil。
  def reopen_blocked_reason
    return unless closed? && (nxt = self.class.for(year + 1))&.closed?

    BlockedReason.new(title: "この年度の締めは解けません", reason: "締めは新しい年度から解きます(次の年度の期首の残高が、この年度の締めから決まるため)。",
      what: "#{nxt.label}が締めてあります", alternative: "代わりに: 先に#{nxt.label}の締めを解いてください。")
  end

  # 会計王へ新規分を書き出せないときの理由(BlockedReason)。書き出せるなら nil。
  def siwake_export_blocked_reason
    return unless provisional?

    BlockedReason.new(title: "まだ書き出せません", reason: "会計王へ書き出せるのは、前の年度を締めたあとです(締める前の仕訳は仮のため)。",
      what: "#{previous.label}をまだ締めていません", alternative: "代わりに: 手続き「事業報告書等の提出」で#{previous.label}を締めてください。")
  end

  # 締めを解く(理由を書く。変更の記録に残る)
  def reopen!(reason:)
    raise ArgumentError, "理由を書いてください" if reason.to_s.strip.empty?
    raise ArgumentError, reopen_blocked_reason.message if reopen_blocked_reason

    Audit.reason!(reason)
    update!(closed_on: nil, closed_by: nil, closed_at: nil)
  end

  def rebuild_next_opening_balances!
    return unless self.class.for(year + 1)

    closing = Ledger::Book.new.statement(year).closing_balances
    accounts = Account.in_year(year + 1).index_by(&:code)
    OpeningBalance.where(fiscal_year: year + 1).destroy_all
    closing.each do |account, amount|
      target = accounts[account.code] or next
      OpeningBalance.create!(fiscal_year: year + 1, account: target, amount:)
    end
  end

  # 締めた年度のデータを直したら、提出済みの事業報告に「再提出が要る」と印を付ける(決まりで付ける節目。docs/adr/0038)。
  # 印は直した操作とは別の操作にし、範囲も分ける(AnnualReport::AUTO_SCOPE。Todo.refresh_auto! と同じ)。
  # 同じ操作に入れると、別の範囲の直した操作を元に戻したときに、まだ残っている直しの分の印まで外れるため。
  # 残った印は害が無い(出し直すか、人が確かめて済ませる)。
  def self.changed_after_close!(years)
    Array(years).uniq.each do |y|
      next unless self.for(y)&.closed?

      report = AnnualReport.find_by(fiscal_year: y)
      next unless report&.submitted_on

      if report.resubmit_needed_on.nil? || (report.resubmitted_on && report.resubmitted_on >= report.resubmit_needed_on)
        Audit.separate_operation(scope: AnnualReport::AUTO_SCOPE, label: "決まりで、#{y}年度の事業報告に「出し直しが要る」を付けた") do
          AnnualReport::Milestone.record!(report, "resubmit_needed", on: Date.current, automatic: true)
        end
      end
    end
  end

  # 前の年度にあって、締めていない後の年度に無い科目・部門を写す(会計王から取り込んだ科目を後の年度でも使えるように)
  def self.propagate_datasets!
    ordered.each_cons(2) do |prev, period|
      next if period.closed?

      Account.copy_year!(prev.year, period.year)
      Department.copy_year!(prev.year, period.year)
    end
  end

  # 年度のデータセット(科目と部門)が無ければ、前の年度から写して作る
  def ensure_dataset!
    prev = self.class.where(year: ...year).maximum(:year)
    return unless prev

    Account.copy_year!(prev, year) unless Account.in_year(year).exists?
    Department.copy_year!(prev, year) unless Department.in_year(year).exists?
  end

  def self.for(year) = find_by(year:)
  def self.years = ordered.pluck(:year)

  def self.state_of(year)
    period = self.for(year)
    return :unknown unless period
    period.state
  end

  def closed? = closed_on.present?
  def previous = self.class.for(year - 1)
  def provisional? = !closed? && previous.present? && !previous.closed?

  def state
    return :closed if closed?
    provisional? ? :provisional : :open
  end

  STATE_LABELS = {closed: "締めた", open: "締める前", provisional: "仮", unknown: ""}.freeze
  def state_label = STATE_LABELS[state]

  def fiscal_year = FiscalYear.new(year)
  def label = "#{year}年度(#{fiscal_year.wareki_label})"

  # 年度の色(5 色で巡回)。デザインシステムのトークン year-1〜5。
  def self.hue(year) = ((year - 2015) % 5) + 1
end
