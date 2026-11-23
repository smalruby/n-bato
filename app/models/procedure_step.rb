# 手続きの中の 1 つの手順の記録。状態は 6 つ(docs/design-system の Stepper):
#   todo 未着手 / current 進行中 / waiting 待ち / done 済み / overdue 期限切れ / skipped 対象外
# 保存するのは done・skipped と、確かめたこと(checks)・メモ。ほかは計算で決める。
class ProcedureStep < ApplicationRecord
  STATUS_LABELS = { "todo" => "未着手", "current" => "進行中", "waiting" => "待ち", "done" => "済み", "overdue" => "期限切れ", "skipped" => "対象外" }.freeze

  belongs_to :procedure_run

  validates :key, presence: true, uniqueness: { scope: :procedure_run_id }
  validate { errors.add(:status, :inclusion) unless self[:status].in?(%w[open done skipped]) } # 保存する値(status メソッドは計算した状態)
  validate { errors.add(:key, "が手続きの定義にありません") if procedure_run && definition.nil? }

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

  def blocked_reason
    return "返事がそろうと押せます(#{wait_items.count { checked?(it) }} / #{wait_items.size})" if wait_items.any? { !checked?(it) }
    return "事業報告がまだありません(事業報告・提出の画面で作ってください)" if definition.effect && run.annual_report.nil?
    if definition.effect == "close_year"
      period = FiscalPeriod.for(run.period)
      return "#{run.period}年度の記録がありません" unless period
      return "提出した日を先に記録してください" unless run.annual_report&.submitted_on
      return "#{period.previous.label}を先に締めてください(年度は古い順に締めます)" if period.previous && !period.previous.closed?
    end

    nil
  end

  # 手順を済みにする。effect がある手順は、事業報告の日付も記録する。
  def complete!(on: Date.current)
    transaction do
      self.status = "done"
      self.completed_on = on
      save!
      case definition.effect
      when "submitted" then run.annual_report.update!(submitted_on: on)
      when "bs_published" then run.annual_report.update!(bs_published_on: on)
      when "close_year" then FiscalPeriod.for(run.period).close!(by: Current.user, on:)
      when "resubmitted" then run.annual_report.update!(resubmitted_on: on)
      end
    end
  end

  # 出る条件のある手順(再提出など)が、いま当てはまるか
  def applicable?
    case definition.only_when
    when "resubmit_needed" then run.annual_report&.resubmit_needed_on.present?
    else true
    end
  end

  def reopen!
    update!(status: "open", completed_on: nil)
  end

  def skip!(reason)
    update!(status: "skipped", completed_on: Date.current, note: reason.presence || note)
  end
end
