# 伏せた文(と、人が選んだときだけ添付)を AI に送る(イベントを作る。docs/adr/0034)
class IncomingRequestMessages::DeliveriesController < ApplicationController
  def create
    req = IncomingRequest.find(params[:incoming_request_id])
    msg = req.messages.find(params[:message_id])
    # 二度押し: もう送ってあれば、AI を呼ばずに伝える
    return redirect_to(incoming_request_path(req, anchor: "thread-end"), alert: IncomingRequestMessage::Delivery::ALREADY) if msg.sent?
    return redirect_to(incoming_request_path(req), alert: "送る前の下書きではありません") unless msg.draft?

    return redirect_to(incoming_request_path(req), alert: "AI の鍵(ANTHROPIC_API_KEY)が設定されていません") unless Bookkeeper::Client.configured?

    Requests::Organizer.new(req).call(msg, masked_body: Masker.new.mask(msg.body).text, send_attachments: params[:send_attachments] == "1")
    redirect_to incoming_request_path(req, anchor: "thread-end")
  rescue ArgumentError => e
    redirect_to incoming_request_path(req, anchor: "thread-end"), alert: e.message
  rescue Bookkeeper::Client::Error => e
    redirect_to incoming_request_path(req, anchor: "draft"), alert: "AI に送れませんでした(#{e.message})"
  end

  private

  def audit_scope = "incoming_request_messages"
end
