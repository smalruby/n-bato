# 設定 › 提出先(見直し第17回、docs/adr/0027)。年度に依存しない。入力するとすぐ保存し、操作履歴に残る。
class FilingDestinationsController < ApplicationController
  include AutosaveResponse

  undoable_screen
  before_action :forbid_auditor, only: %i[create update destroy]

  def index
    @destinations = FilingDestination.ordered.includes(:confirmations)
    @search = FilingDestinationSearch.latest
    @ai_ready = Bookkeeper::Client.configured?
    @support_url = FilingSamplesController.support_url
  end

  def create
    kind = params[:kind].presence_in(FilingDestination::KINDS.keys) || "other"
    d = FilingDestination.create!(kind:, position: FilingDestination.maximum(:position).to_i + 1)
    Audit.label!("提出先を足した: #{d.kind_label}")
    redirect_to filing_destinations_path(anchor: "dest-#{d.id}"), notice: "#{d.kind_label}を足しました。窓口を書いて、確かめてください"
  end

  def update
    d = FilingDestination.find(params[:id])
    d.assign_attributes(params.require(:filing_destination).permit(*FilingDestination::CONTENT_FIELDS, :notes))
    Audit.label!("提出先を直した: #{d.kind_label} #{d.name}")
    d.save
    respond_to do |format|
      format.json { autosave_response(d, state: d.state_label) }
      format.html { redirect_to filing_destinations_path(anchor: "dest-#{d.id}") }
    end
  end

  def destroy
    d = FilingDestination.find(params[:id])
    Audit.label!("提出先を消した: #{d.kind_label} #{d.name}")
    d.destroy!
    redirect_to filing_destinations_path, notice: "提出先を消しました(元に戻せます)"
  end

  private

  def forbid_auditor = (redirect_to(filing_destinations_path, alert: "監査の役割では直せません") if Current.user&.auditor?)
end
