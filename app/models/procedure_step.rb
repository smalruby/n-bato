# 手続きの中の 1 つの手順の記録。状態は 6 つ(docs/design-system の Stepper):
#   todo 未着手 / current 進行中 / waiting 待ち / done 済み / overdue 期限切れ / skipped 対象外
# 保存するのは done・skipped と、確かめたこと(checks)・メモ。ほかは計算で決める。
# 長いイベント(docs/adr/0038)。済みにした・対象外にした・済みを取り消したは詳細のイベント ProcedureStep::StatusChange。
# 保存する状態(列の status・completed_on)は「いまの状態」で、ProcedureStep::StatusChange.change! だけが書き換える(照合は model:verify)。
# 確かめたこと(checks)・メモは作業の中身で、ふつうに直してよい(操作履歴に残る。ADR-0006)。
class ProcedureStep < ApplicationRecord
  STATUS_LABELS = {"todo" => "未着手", "current" => "進行中", "waiting" => "待ち", "done" => "済み", "overdue" => "期限切れ", "skipped" => "対象外"}.freeze
  STORED_STATUSES = %w[open done skipped].freeze
  STATE_COLUMNS = %w[status completed_on].freeze

  belongs_to :procedure_run
  has_many :status_changes, -> { order(:id) }, class_name: "ProcedureStep::StatusChange", dependent: :restrict_with_error

  validates :key, presence: true, uniqueness: {scope: :procedure_run_id}
  validate { errors.add(:status, :inclusion) unless self[:status].in?(STORED_STATUSES) } # 保存する値(status メソッドは計算した状態)
  validate { errors.add(:key, "が手続きの定義にありません") if procedure_run && definition.nil? }
  validate :state_written_by_status_change

  def self.model_name_label = "手続きの手順"

  # 元に戻す・やり直すのあとに、状態を確かめる手順(Audit.check_states!)
  def self.audit_state_owner(change) = find_by(id: change.auditable_id)

  # 保存する状態は、最後の変化(id の順)から決まる。変化が無ければ open(docs/adr/0005)
  def self.state_for(change)
    status = change&.status || "open"
    {"status" => status, "completed_on" => status.in?(%w[done skipped]) ? change.completed_on : nil}
  end

  def derived_state = ProcedureStep.state_for(status_changes.max_by(&:id))

  def state_mismatches
    want = derived_state
    STATE_COLUMNS.reject { Audit.dump(self[it]).to_s == Audit.dump(want[it]).to_s }
  end

  # いまの状態の列を書き換える。呼ぶのは ProcedureStep::StatusChange.change! だけ。まだ保存していない手順なら作る。
  def apply_state!(state)
    @applying_state = true
    update!(state)
  ensure
    @applying_state = false
  end

  def definition = procedure_run.definition.step(key)
  def run = procedure_run

  def status
    return self[:status] if self[:status].in?(%w[done skipped])
    return "skipped" if definition.only_when && !applicable?
    return "done" if done_by_record?
    return "overdue" if definition.deadline? && run.due_on < Date.current
    return "waiting" if started? && wait_items.any? { !checked?(it) }

    started? ? "current" : "todo"
  end

  def status_label = STATUS_LABELS.fetch(status)
  def started? = checks.present? || note.present?

  # 確かめること(定義の checks)と、相手の返事を待つもの(waits・waits_from)
  def check_items = definition.checks
  def wait_items = definition.waits + people_waited_for
  def all_items = check_items + wait_items
  def checked?(label) = checks.key?(label)
  def checked_on(label) = checks[label]&.then { Date.parse(it) }

  def check!(label, on: Date.current)
    self.checks = checks.merge(label => on.iso8601)
  end

  def uncheck!(label)
    self.checks = checks.except(label)
  end

  # 書面による同意などで、返事を待つ人。役員・正会員の記録から出す。
  def people_waited_for
    case definition.waits_from
    when "board" then OfficerTerm.serving_on(Date.current).select { it.role != "auditor" }.map { "#{it.person.name}(#{it.role_label})" }
    when "officer_candidates" then OfficerTerm.serving_on(Date.current).map { "#{it.person.name}(#{it.role_label})" }
    when "regular_members" then Membership.in_fiscal_year(FiscalYear.current.year).where(kind: "regular").includes(:person).map { it.person.name }
    else []
    end
  end

  # ほかの記録から済んだと分かる手順(事業報告の承認日・提出日など)
  def done_by_record?
    report = run.annual_report
    case definition.done_when || definition.effect
    when "approved" then report&.approved_on.present?
    when "submitted" then report&.submitted_on.present?
    when "bs_published" then report&.bs_published_on.present?
    when "close_year" then FiscalPeriod.for(run.period)&.closed? || false
    when "resubmitted" then report&.resubmitted_on.present? && report.resubmit_needed_on.present? && report.resubmitted_on >= report.resubmit_needed_on
    else false
    end
  end

  # 済みにできないときの理由(BlockedReason)。済みにできるなら nil。画面の (i) と、コントローラーの断りの文で使う。
  def complete_blocked_reason
    if wait_items.any? { !checked?(it) }
      return BlockedReason.new(title: "まだ済みにできません", reason: "返事を待つ手順は、返事がそろってから済みにします。",
        what: "返事がそろったのは #{wait_items.count { checked?(it) }} / #{wait_items.size} です", link_label: "返事を待つものを見る", link_target: "#waits",
        alternative: "代わりに: 返事が来たら「返事を待つもの」にチェックを入れてください。")
    end
    if definition.effect && run.annual_report.nil?
      return BlockedReason.new(title: "まだ済みにできません", reason: "この手順は事業報告に日付を記録するので、先に事業報告が要ります。",
        what: "#{run.period}年度の事業報告がまだありません", alternative: "代わりに: 事業報告・提出の画面で、この年度の事業報告を作ってください。")
    end
    close_year_blocked_reason if definition.effect == "close_year"
  end

  # 済みにできないときの理由の文(運用のスクリプトなどで使う。中身は complete_blocked_reason)
  def blocked_reason = complete_blocked_reason&.message

  # 済みを取り消せないときの理由(BlockedReason)。取り消せる・取り消すものが無いなら nil。
  def reopen_blocked_reason
    if self[:status] == "done" && definition.final?
      BlockedReason.new(title: "この手順は取り消せません", reason: "提出・届出・登記・年度の締めなどを記録した手順は、元に戻せない操作なので、済みを取り消せません。",
        what: "#{completed_on&.strftime("%Y/%m/%d")} に済みにしました(#{definition.final_label || definition.title})",
        alternative: REOPEN_INSTEAD[definition.effect])
    elsif self[:status] == "open" && status == "done"
      BlockedReason.new(title: "この手順は取り消せません", reason: "ほかの記録(事業報告の日付・年度の締め)から済んだと分かった手順なので、ここでは取り消せません。",
        alternative: REOPEN_INSTEAD[definition.done_when || definition.effect])
    end
  end

  REOPEN_INSTEAD = {
    "approved" => "代わりに: 日付の打ち間違いは、事業報告・提出の画面で直せます。",
    "submitted" => "代わりに: 日付の打ち間違いは、事業報告・提出の画面で直せます。",
    "bs_published" => "代わりに: 日付の打ち間違いは、事業報告・提出の画面で直せます。",
    "resubmitted" => "代わりに: 日付の打ち間違いは、事業報告・提出の画面で直せます。",
    "close_year" => "代わりに: 締めた年度を直すときは、決算の画面の「締めを解く」を使ってください。"
  }.freeze

  # 出る条件のある手順(再提出など)が、いま当てはまるか
  def applicable?
    case definition.only_when
    when "resubmit_needed" then run.annual_report&.resubmit_needed_on.present?
    else true
    end
  end

  private

  def close_year_blocked_reason
    period = FiscalPeriod.for(run.period)
    unless period
      return BlockedReason.new(title: "まだ締められません", reason: "年度を締めるには、その年度の記録(科目・仕訳)が要ります。", what: "#{run.period}年度の記録がありません")
    end
    unless run.annual_report&.submitted_on
      return BlockedReason.new(title: "まだ締められません", reason: "年度を締めるのは、事業報告書等を所轄庁に提出したあとです。", what: "提出した日がまだ記録されていません",
        alternative: "代わりに: 先に「提出した日を記録する」の手順を済ませてください。")
    end
    return unless period.previous && !period.previous.closed?

    BlockedReason.new(title: "まだ締められません", reason: "年度は古い順に締めます。", what: "#{period.previous.label}をまだ締めていません",
      alternative: "代わりに: 先に#{period.previous.label}を締めてください。")
  end

  # 保存する状態は、状態の変化からだけ書く(作るときは open)。元に戻す・やり直すは検証を通さずに書くので止めない。
  def state_written_by_status_change
    return if @applying_state

    if new_record?
      errors.add(:base, "手順は open で作ってください(済みにするときは ProcedureStep::StatusChange.change!)") unless self[:status] == "open" && completed_on.nil?
    elsif (changed = STATE_COLUMNS & changed_attribute_names_to_save).any?
      errors.add(:base, "#{changed.join("・")} は直接書き換えません。ProcedureStep::StatusChange.change!(手順, status: …) を使ってください")
    end
  end
end
