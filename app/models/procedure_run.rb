# 年に一度の手続き 1 回分。手順(ProcedureStep)の進み具合を持つ。
# 長いイベント(docs/adr/0038)。始めるのは ProcedureRun.start!。いまの状態(済んだ数・次にやること)は手順から毎回決まる(列には持たない)。
class ProcedureRun < ApplicationRecord
  has_many :procedure_steps, dependent: :restrict_with_error

  # 手続きを始める。もう始めてあれば、その手続きを返す(二度押しでも同じ)。
  def self.start!(kind:, period:)
    find_by(kind:, period:) || Audit.operation do
      transaction(requires_new: true) do
        run = create!(kind:, period:)
        Audit.label!("手続きを始めた: #{run.name}(#{run.period_label})")
        run
      end
    end
  rescue ActiveRecord::RecordNotUnique
    where(kind:, period:).take!
  end

  validates :kind, inclusion: {in: -> { ProcedureDefinition.all.keys }}
  validates :period, presence: true, uniqueness: {scope: :kind}

  scope :ordered, -> { order(period: :desc, kind: :asc) }

  def definition = ProcedureDefinition.find(kind)
  def name = definition.name
  def period_label = definition.period_label(period)
  def due_on = definition.due_on(period)
  def days_left(today = Date.current) = (due_on - today).to_i

  # 手順の記録。まだ無い手順は保存せずに作る(開いただけでは記録を増やさない)。
  def step(key)
    procedure_steps.find { it.key == key.to_s } || procedure_steps.build(key: key.to_s)
  end

  def steps = definition.steps.map { step(it.key) }
  def previous_run = ProcedureRun.where(kind:).where(period: ...period).order(period: :desc).first

  # 事業報告(kind が annual_report のときの対象)
  def annual_report
    return unless kind == "annual_report"

    @annual_report ||= AnnualReport.find_by(fiscal_year: period)
  end

  def done_count = steps.count { it.status.in?(%w[done skipped]) }
  def waiting_count = steps.count { it.status == "waiting" }
  def finished? = done_count == steps.size
  def next_step = steps.find { !it.status.in?(%w[done skipped waiting]) }

  def overdue?(today = Date.current) = !finished? && due_on < today
end
