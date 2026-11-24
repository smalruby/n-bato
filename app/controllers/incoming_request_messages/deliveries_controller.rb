# 伏せた文(と、人が選んだときだけ添付)を AI に送る(イベントを作る。docs/adr/0034)
class IncomingRequestMessages::DeliveriesController < ApplicationController
  def create
    req = IncomingRequest.find(params[:incoming_request_id])
    msg = req.messages.drafts.find(params[:message_id])
    return redirect_to(incoming_request_path(req), alert: "AI の鍵(ANTHROPIC_API_KEY)が設定されていません") unless Bookkeeper::Client.configured?

    Requests::Organizer.new(req).call(msg, masked_body: Masker.new.mask(msg.body).text, send_attachments: params[:send_attachments] == "1")
    redirect_to incoming_request_path(req, anchor: "thread-end")
  rescue Bookkeeper::Client::Error => e
    redirect_to incoming_request_path(req, anchor: "draft"), alert: "AI に送れませんでした(#{e.message})"
  end

  private

  def audit_scope = "incoming_request_messages"
end
