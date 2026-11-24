# AI の案を「この案で決める」(イベントを作る。docs/adr/0034)。元に戻せる。
class IncomingRequestMessages::AdoptionsController < ApplicationController
  def create
    req = IncomingRequest.find(params[:incoming_request_id])
    created, updated = IncomingRequestMessage::Adoption.adopt!(req.messages.find(params[:message_id]), by: Current.user)
    redirect_to incoming_request_path(req, anchor: "todos"), notice: "やることを #{created.size} 件作り、#{updated.size} 件直しました(元に戻せます)"
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to incoming_request_path(req), alert: e.message
  end

  private

  def audit_scope = "incoming_request_messages"
end
