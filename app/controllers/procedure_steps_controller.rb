# 手順の記録(確かめたこと・メモは自動保存)。済みにする・対象外にする・済みを取り消すは ProcedureSteps::StatusChangesController。
class ProcedureStepsController < ApplicationController
  include AutosaveResponse

  before_action :set_step

  def update
    (params[:checks] || {}).each do |label, value|
      next unless @step.all_items.include?(label)

      (value == "1") ? @step.check!(label) : @step.uncheck!(label)
      Audit.label!("#{(value == "1") ? "確認" : "確認を外した"}: #{label}(#{@step.definition.title})")
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

  private

  def audit_scope = "procedure:#{params[:procedure_id]}"

  def set_step
    @run = ProcedureRun.find(params[:procedure_id])
    @step = @run.step(params[:key])
    raise ActiveRecord::RecordNotFound unless @step.definition
  end
end
