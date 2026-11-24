# 年に一度の手続き(手順の画面)。docs/design-system の Procedure。
class ProceduresController < ApplicationController
  undoable_screen

  def index
    # 操作している年度の手続き(事業報告書等の提出は、その報告の年度に属する)
    @runs = ProcedureRun.ordered.where(period: Current.working_year).to_a
    started = ProcedureRun.pluck(:kind, :period)
    @startable = startable_periods.select { |_, period| period == Current.working_year }.reject { started.include?(it) }
  end

  def show
    @run = ProcedureRun.find(params[:id])
    @steps = @run.steps
    @step = @run.step(params[:step].presence || @run.next_step&.key || @steps.first.key)
    @previous = @run.previous_run
  end

  def create
    run = ProcedureRun.start!(kind: params.require(:kind), period: Integer(params.require(:period)))
    redirect_to procedure_path(run)
  end

  private

  def audit_scope = params[:id] ? "procedure:#{params[:id]}" : "procedures"

  # まだ始めていない手続き(これまでの年度と、今年の改選)
  def startable_periods
    from = Organization.current&.settings&.dig("compliance_from")&.to_i || FiscalYear.current.year - 1
    reports = (from..FiscalYear.current.year - 1).map { [ "annual_report", it ] }
    elections = (from..Date.current.year).select(&:even?).map { [ "officer_election", it ] }
    (reports + elections).sort_by { -it.last }
  end
end
