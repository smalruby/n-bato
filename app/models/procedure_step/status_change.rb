# 手続きの手順の状態を変えた(イベント。日時は changed_at)。docs/adr/0038
# 済みにした(done。済んだ日 completed_on)・対象外にした(skipped。理由は note)・済みを取り消した(open)の 3 つを、変えたあとの状態で表す。
# 手順の保存する状態(status・completed_on)は、最後の変化(id の順)から決まる。
# 済みにした手順に効き目(effect)があれば、同じ操作の中で事業報告の節目・年度の締めも記録する。
# 定義で final の手順を済みにするのは、元に戻せない操作。ほかはふつうの操作なので元に戻せる(元に戻すと、この変化も消える)。
class ProcedureStep::StatusChange < ApplicationRecord
  include EventRecord

  event_of :changed_at, entry: :change!

  STATUSES = {"done" => "済みにした", "skipped" => "対象外にした", "open" => "済みを取り消した"}.freeze

  belongs_to :procedure_step
  belongs_to :changed_by, class_name: "User", optional: true

  validates :status, inclusion: {in: STATUSES.keys}

  def self.model_name_label = "手順の状態の変化"
  def self.audit_state_owner(change) = ProcedureStep.find_by(id: change.value("procedure_step_id"))

  def audit_fiscal_year = procedure_step&.procedure_run&.period

  # status: done・skipped・open。on は済んだ日(done)。reason は対象外の理由(skipped。空なら前のメモを残す)。
  # いまの保存する状態と同じなら何もしない(nil を返す)。済みにした final の手順を変える・optional でない手順を対象外にするのは ArgumentError。
  # 返事がそろっているかなど(blocked_reason)は画面が確かめる(運用のスクリプトからは、これまでどおり確かめずに済みにできる)。
  def self.change!(step, status:, on: Date.current, reason: "", by: Current.user, at: Time.current)
    raise ArgumentError, "状態が分かりません" unless STATUSES.key?(status)

    # 操作の外(rake・運用のスクリプト)で呼ばれても、手順の列・イベント・効き目を 1 つの操作にする(入れ子なら外側の操作にまとめる)
    Audit.operation do
      transaction(requires_new: true) do
        # 二度押しで、もう一方が先に変えていないか・先に手順の記録を作っていないか(古い記録を読んでいないか)
        if step.persisted?
          step.reload
        elsif (saved = ProcedureStep.find_by(procedure_run_id: step.procedure_run_id, key: step.key))
          step = saved
        end
        next nil if step[:status] == status

        # final の手順を済みにしたのは元に戻せない操作(提出した日など)。そのあとは対象外にも取り消しにもしない
        if step[:status] == "done" && step.definition.final?
          raise ArgumentError, status == "open" ? step.reopen_blocked_reason.message : "この手順は済みにしたので、もう変えられません"
        end
        # 対象外にできるのは、定義(config/procedures)で optional の手順だけ(画面にもその手順だけボタンを出す)
        raise ArgumentError, "この手順は対象外にできません" if status == "skipped" && !step.definition.optional?

        completed_on = case status
        when "open" then nil
        when "done" then on
        else Date.current
        end
        change = new(status:, completed_on:, note: (status == "skipped") ? reason.to_s.strip : "", changed_by: by, changed_at: at)
        attrs = ProcedureStep.state_for(change)
        attrs["note"] = change.note if status == "skipped" && change.note.present?
        # 手順を先に書く(元に戻すの表示が「状態 open → done」になるように)
        step.apply_state!(attrs)
        change.procedure_step = step
        change.save!
        apply_effect!(step, on, by) if status == "done"
        label!(step, status)
        change
      end
    end
  rescue ActiveRecord::RecordNotUnique
    # 二度押しで、まだ無かった手順の記録をもう一方が先に作った。セーブポイントごと取り消してある
    raise ArgumentError, "もう#{STATUSES.fetch(status).delete_suffix("た")}てあります"
  end

  # 済みにした手順の効き目(config/procedures の effect)
  def self.apply_effect!(step, on, by)
    report = step.run.annual_report
    case step.definition.effect
    when "submitted" then AnnualReport::Milestone.record!(report, "submitted", on:, by:)
    when "bs_published" then AnnualReport::Milestone.record!(report, "bs_published", on:, by:)
    when "resubmitted" then AnnualReport::Milestone.record!(report, "resubmitted", on:, by:)
    when "close_year"
      period = FiscalPeriod.for(step.run.period)
      period.close!(by:, on:) unless period.closed? # もう締めてある年度(取り込んだ記録など)は、済みの記録だけ
    end
  end

  def self.label!(step, status)
    defn = step.definition
    case status
    when "done" then defn.final? ? Audit.final!(defn.final_label || defn.title) : Audit.label!("済みにした: #{defn.title}")
    when "skipped" then Audit.label!("対象外にした: #{defn.title}")
    else Audit.label!("済みを取り消した: #{defn.title}")
    end
  end
  private_class_method :apply_effect!, :label!

  def status_label = STATUSES.fetch(status)
end
