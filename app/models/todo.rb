# やること(デザインシステム「やること」)。年度ごとのデータセットの外に置く。1 件の対象は 1 つの年度か年度なし。
class Todo < ApplicationRecord
  STATUSES = { "todo" => "未着手", "doing" => "作業中", "wait" => "待ち", "done" => "済み" }.freeze
  KINDS = { "screen" => "画面", "document" => "書類", "ask" => "人に聞く", "window" => "電話・窓口" }.freeze

  # 「開く」で移る画面。AI はこの中から選ぶ。年度に関わるものは、開く前にその年度へ切り替える。
  TARGETS = {
    "" => [ "(n-bato の画面なし)", nil ],
    "journal_entries" => [ "仕訳", ->(h) { h.journal_entries_path } ],
    "vouchers" => [ "証憑・AI 仕訳", ->(h) { h.vouchers_path } ],
    "fiscal_year" => [ "会計(年度)", ->(h) { h.fiscal_years_path } ],
    "balance_checks" => [ "残高照合", ->(h) { h.balance_checks_path } ],
    "people" => [ "会員・役員", ->(h) { h.people_path } ],
    "procedures" => [ "手続き", ->(h) { h.procedures_path } ],
    "annual_reports" => [ "事業報告・提出", ->(h) { h.annual_reports_path } ],
    "resolutions" => [ "決議", ->(h) { h.resolutions_path } ],
    "registrations" => [ "登記", ->(h) { h.registrations_path } ],
    "accounts" => [ "科目と部門", ->(h) { h.accounts_path } ],
    "organization" => [ "法人情報", ->(h) { h.organization_path } ],
    "changes" => [ "変更の記録", ->(h) { h.changes_path } ]
  }.freeze

  # 自動で済みにする決まり。n-bato の記録で確かめられるものだけ。
  DONE_RULES = {
    "" => "人が済みにする",
    "annual_report_submitted" => "その年度の事業報告書等の提出を記録したら",
    "year_closed" => "その年度を締めたら"
  }.freeze

  # 待ちが解ける決まり(待ちのやることを作業中に戻す)。n-bato の記録で分かるものだけ。
  RESUME_RULES = {
    "" => "人が戻す",
    "registration_completed" => "登記の申請が完了したら"
  }.freeze

  belongs_to :incoming_request, optional: true

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  validates :kind, inclusion: { in: KINDS.keys }
  validates :target, inclusion: { in: TARGETS.keys }
  validates :done_rule, inclusion: { in: DONE_RULES.keys }
  validates :resume_rule, inclusion: { in: RESUME_RULES.keys }

  scope :unfinished, -> { where.not(status: "done") }

  def status_label = STATUSES.fetch(status)
  def resume_rule_label = RESUME_RULES.fetch(resume_rule)

  # 決まりに合う「待ち」のやることを作業中に戻す。戻したやることを返す。
  def self.resume!(rule, note:)
    where(status: "wait", resume_rule: rule).to_a.each do |t|
      t.update!(status: "doing", waiting_on: "", note: [ t.note.presence, note ].compact.join("\n"))
    end
  end

  def kind_label = KINDS.fetch(kind)
  def target_label = TARGETS.dig(target, 0)
  def done? = status == "done"
  def overdue?(today = Date.current) = !done? && due_on.present? && due_on < today

  def target_path(helpers) = TARGETS.dig(target, 1)&.call(helpers)

  # 自動で済みにできるか(できるなら、何をもって済みにしたかを返す)
  def auto_done_reason
    return if done? || done_rule.blank? || fiscal_year.nil?

    case done_rule
    when "annual_report_submitted"
      d = AnnualReport.find_by(fiscal_year:)&.submitted_on
      d && "#{fiscal_year}年度の提出の記録(#{d})で済みにした"
    when "year_closed"
      p = FiscalPeriod.for(fiscal_year)
      p&.closed? && "#{fiscal_year}年度を締めた記録で済みにした"
    end
  end

  def self.refresh_auto!
    unfinished.where.not(done_rule: "").find_each do |t|
      next unless (why = t.auto_done_reason)

      t.update!(status: "done", done_at: Time.current, done_by: "auto", done_note: why)
    end
  end

  # 締めた年度を直すときの理由の欄に、最初から入れておく文
  def reason_hint = [ incoming_request&.title, title ].compact.join(": ")
end
