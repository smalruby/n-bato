# 依頼のやることが全部済んだら、AI に送付状(返信)の下書きを作ってもらう。送るのは人。
class IncomingRequests::CoverLettersController < ApplicationController
  def create
    req = IncomingRequest.find(params[:incoming_request_id])
    return redirect_to(incoming_request_path(req), alert: "AI の鍵(ANTHROPIC_API_KEY)が設定されていません") unless Bookkeeper::Client.configured?

    Requests::CoverLetter.new(req).call
    redirect_to incoming_request_path(req, anchor: "cover"), notice: "送付状の下書きを作りました。直してから使ってください"
  rescue Bookkeeper::Client::Error => e
    redirect_to incoming_request_path(req), alert: "下書きを作れませんでした(#{e.message})"
  end

  private

  def audit_scope = "incoming_requests"
end
