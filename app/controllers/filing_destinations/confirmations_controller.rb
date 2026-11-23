# 提出先を人が確かめた(イベントを作る。docs/adr/0008)
class FilingDestinations::ConfirmationsController < ApplicationController
  def create
    d = FilingDestination.find(params[:filing_destination_id])
    return redirect_to(filing_destinations_path, alert: "監査の役割では確かめられません") if Current.user&.auditor?

    FilingDestination::Confirmation.confirm!(d, by: Current.user)
    redirect_to filing_destinations_path(anchor: "dest-#{d.id}"), notice: "#{d.kind_label}(#{d.name})を確認済みにしました"
  rescue ArgumentError => e
    redirect_to filing_destinations_path(anchor: "dest-#{d.id}"), alert: e.message
  end

  private

  def audit_scope = "filing_destinations"
end
