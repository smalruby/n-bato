# 手順の記録(確かめたこと・メモは自動保存、済みにする・対象外にする・済みを取り消す)。
class ProcedureStepsController < ApplicationController
  include AutosaveResponse
  before_action :set_step

  def update
    (params[:checks] || {}).each do |label, value|
      next unless @step.all_items.include?(label)

      value == "1" ? @step.check!(label) : @step.uncheck!(label)
      Audit.label!("#{value == '1' ? '確認' : '確認を外した'}: #{label}(#{@step.definition.title})")
    end
    if params.key?(:note)
      @step.note = params[:note]
      Audit.label!("メモ: #{@step.definition.title}")
    end
    @step.save
    respond_to do |format|
      format.json { autosave_response(@step) }
      format.html { redirect_to procedure_path(@run, step: @step.key) }
    end
  end

  def complete
    if (reason = @step.blocked_reason)
      return redirect_to(procedure_path(@run, step: @step.key), alert: reason)
    end

    if @step.definition.final?
      Audit.final!("#{@step.definition.final_label || @step.definition.title}")
    else
      Audit.label!("済みにした: #{@step.definition.title}")
    end
    @step.complete!(on: params[:completed_on].presence&.then { Date.parse(it) } || Date.current)
    redirect_to procedure_path(@run, step: @run.next_step&.key || @step.key),
                notice: @step.definition.final? ? "#{@step.definition.title}を記録しました" : "#{@step.definition.title}を済みにしました(元に戻せます)"
  end

  def reopen
    if @step.definition.final?
      return redirect_to(procedure_path(@run, step: @step.key), alert: "この手順は取り消せません")
    end

    Audit.label!("済みを取り消した: #{@step.definition.title}")
    @step.reopen!
    redirect_to procedure_path(@run, step: @step.key), notice: "済みを取り消しました"
  end

  def skip
    Audit.label!("対象外にした: #{@step.definition.title}")
    @step.skip!(params[:reason])
    redirect_to procedure_path(@run, step: @run.next_step&.key || @step.key), notice: "#{@step.definition.title}を対象外にしました(元に戻せます)"
  end

  private

  def audit_scope = "procedure:#{params[:procedure_id]}"

  def set_step
    @run = ProcedureRun.find(params[:procedure_id])
    @step = @run.step(params[:key])
    raise ActiveRecord::RecordNotFound unless @step.definition
  end
end
