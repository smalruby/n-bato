# やること(デザインシステム「やること」)。年度ごとのデータセットの外に置く。1 件の対象は 1 つの年度か年度なし。
# 長いイベント(docs/adr/0034)。状態の変化(作業中・待ち・済み・未着手に戻す)は詳細のイベント Todo::StatusChange。
# status・waiting_on・done_at・done_by・done_note は「いまの状態」で、Todo::StatusChange.change! だけが書き換える(照合は model:verify)。
# 題・期限・メモなどの中身は、ふつうに直してよい(操作履歴に残る)。
class Todo < ApplicationRecord
  STATUSES = {"todo" => "未着手", "doing" => "作業中", "wait" => "待ち", "done" => "済み"}.freeze
  KINDS = {"screen" => "画面", "document" => "書類", "ask" => "人に聞く", "window" => "電話・窓口"}.freeze

  # 「開く」で移る画面。AI はこの中から選ぶ。年度に関わるものは、開く前にその年度へ切り替える。
  TARGETS = {
    "" => ["(n-bato の画面なし)", nil],
    "journal_entries" => ["仕訳", ->(h) { h.journal_entries_path }],
    "vouchers" => ["証憑・AI 仕訳", ->(h) { h.vouchers_path }],
    "fiscal_year" => ["会計(年度)", ->(h) { h.fiscal_years_path }],
    "balance_checks" => ["残高照合", ->(h) { h.balance_checks_path }],
    "people" => ["会員・役員", ->(h) { h.people_path }],
    "procedures" => ["手続き", ->(h) { h.procedures_path }],
    "annual_reports" => ["事業報告・提出", ->(h) { h.annual_reports_path }],
    "resolutions" => ["決議", ->(h) { h.resolutions_path }],
    "registrations" => ["登記", ->(h) { h.registrations_path }],
    "accounts" => ["科目と部門", ->(h) { h.accounts_path }],
    "organization" => ["法人情報", ->(h) { h.organization_path }],
    "changes" => ["変更の記録", ->(h) { h.changes_path }]
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

  # いまの状態の列。直接は書き換えない(Todo::StatusChange.change! を使う)
  STATE_COLUMNS = %w[status waiting_on done_at done_by done_note].freeze

  belongs_to :incoming_request, optional: true
  has_many :status_changes, -> { order(:changed_at, :id) }, class_name: "Todo::StatusChange", dependent: :restrict_with_error

  validates :title, presence: true
  validates :status, inclusion: {in: STATUSES.keys}
  validates :kind, inclusion: {in: KINDS.keys}
  validates :target, inclusion: {in: TARGETS.keys}
  validates :done_rule, inclusion: {in: DONE_RULES.keys}
  validates :resume_rule, inclusion: {in: RESUME_RULES.keys}
  validate :state_written_by_status_change

  scope :unfinished, -> { where.not(status: "done") }

  def status_label = STATUSES.fetch(status)
  def resume_rule_label = RESUME_RULES.fetch(resume_rule)

  # 決まりに合う「待ち」のやることを作業中に戻す。戻したやることを返す。
  # 操作の外(rake など)で呼ばれても、メモと状態の変化を 1 つの操作にする(入れ子なら外側の操作にまとめる)。
  def self.resume!(rule, note:)
    Audit.operation do
      where(status: "wait", resume_rule: rule).to_a.each do |t|
        t.update!(note: [t.note.presence, note].compact.join("\n"))
        Todo::StatusChange.change!(t, status: "doing", note:, automatic: true)
      end
    end
  end

  # 状態の変化から決まる、いまの状態(docs/adr/0005)。change: 最後の変化(まだ保存していないものでもよい)。無ければ未着手。
  def self.state_for(change)
    st = change&.status || "todo"
    done = st == "done"
    {"status" => st, "waiting_on" => (st == "wait") ? change.waiting_on.to_s : "",
     "done_at" => done ? change.changed_at : nil, "done_by" => if done
                                                                 change.automatic ? "auto" : "user"
                                                               else
                                                                 ""
                                                               end,
     "done_note" => done ? change.note.to_s : ""}
  end

  def self.model_name_label = "やること"

  # 元に戻す・やり直すのあとに、状態を確かめるやること(Audit.check_states!)
  def self.audit_state_owner(change) = find_by(id: change.auditable_id)

  def latest_status_change = status_changes.max_by { [it.changed_at, it.id.to_i] }
  def derived_state = Todo.state_for(latest_status_change)

  # いまの状態の列を書き換える。呼ぶのは Todo::StatusChange.change! だけ。
  def apply_state!(state)
    @applying_state = true
    update!(state)
  ensure
    @applying_state = false
  end

  # いまの状態の列が、状態の変化と食い違っている列の名前(model:verify)。done_by は「自動かどうか」だけを比べる。
  def state_mismatches
    want = derived_state
    keys = %w[status]
    keys << "waiting_on" if want["status"] == "wait"
    keys.push("done_at", "done_note") if want["status"] == "done"
    diff = keys.reject { Audit.dump(self[it]).to_s == Audit.dump(want[it]).to_s }
    diff << "done_by" if want["status"] == "done" && (done_by == "auto") != (want["done_by"] == "auto")
    diff
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

  # 画面を開いたとき(GET)に呼ぶ。何件済みにしても 1 つの操作にし、範囲は todos_auto にする(docs/adr/0034)。
  # やることの画面の「元に戻す」では戻さない(戻しても、次に開いたときにまた済みになるため)。
  AUTO_SCOPE = "todos_auto"
  def self.refresh_auto!
    Audit.operation(scope: AUTO_SCOPE) do
      done = unfinished.where.not(done_rule: "").to_a.filter_map do |t|
        next unless (why = t.auto_done_reason)

        Todo::StatusChange.change!(t, status: "done", note: why, automatic: true)
      end
      Audit.label!("決まりで、やることを #{done.size} 件済みにした") if done.size > 1
      done
    end
  end

  # 締めた年度を直すときの理由の欄に、最初から入れておく文
  def reason_hint = [incoming_request&.title, title].compact.join(": ")

  private

  # いまの状態の列は、状態の変化からだけ書く(作るときは未着手のまま)。元に戻す・やり直すは検証を通さずに書くので止めない。
  def state_written_by_status_change
    return if @applying_state

    if new_record?
      fresh = STATE_COLUMNS.all? { Audit.dump(self[it]).to_s == Audit.dump(Todo.state_for(nil)[it]).to_s }
      errors.add(:base, "やることは未着手で作ってください(状態を変えるときは Todo::StatusChange.change!)") unless fresh
    elsif (changed = STATE_COLUMNS & changed_attribute_names_to_save).any?
      errors.add(:base, "#{changed.join("・")} は直接書き換えません。Todo::StatusChange.change!(やること, status: …) を使ってください")
    end
  end
end
