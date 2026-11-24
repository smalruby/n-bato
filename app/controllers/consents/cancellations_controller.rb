# 同意の記録を取り消す(取消のイベントを作る。同意の記録は消さない。docs/adr/0008・0038)。
class Consents::CancellationsController < ApplicationController
  def create
    resolution = ::Resolution.find(params[:resolution_id])
    consent = resolution.all_consents.find(params[:consent_id])
    Consent::Cancellation.cancel!(consent, by: Current.user)
    redirect_to resolution, notice: "同意の記録を取り消しました"
  rescue ArgumentError => e
    redirect_to resolution, alert: e.message
  end

  private

  def audit_scope = "consents"
end
