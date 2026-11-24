# 依頼を解決にする(イベントを作る。docs/adr/0034)。やることが全部済んでいなければ、force=1 のときだけ。
class IncomingRequests::SettlementsController < ApplicationController
  def create
    req = IncomingRequest.find(params[:incoming_request_id])
    IncomingRequest::Settlement.settle!(req, force: params[:force] == "1", by: Current.user)
    redirect_to incoming_request_path(req), notice: "依頼を解決にしました(元に戻せます)"
  rescue ArgumentError => e
    redirect_to incoming_request_path(req), alert: e.message
  end

  private

  def audit_scope = "incoming_requests"
end
