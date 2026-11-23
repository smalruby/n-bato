# 外から届いた依頼と、依頼ごとの AI との対話(デザインシステム「やること」の RequestThread)。
class IncomingRequestsController < ApplicationController
  undoable_screen
  before_action :set_request, only: %i[show resolve cover_letter]

  def new; end

  # 依頼を作り、最初の発言(メール本文と添付)を下書きとして置く。AI にはまだ送らない(伏せた文を人が確かめてから)。
  def create
    text = params[:body].to_s.strip
    return redirect_to(new_incoming_request_path, alert: "依頼の文(メールの本文など)を貼ってください") if text.empty?

    req = IncomingRequest.create!
    IncomingRequestMessages.draft!(req, text, Array(params[:files]).compact_blank)
    redirect_to incoming_request_path(req, anchor: "draft")
  end

  def show
    Todo.refresh_auto!
    @draft = @req.messages.where(role: "user", sent_at: nil).last
    @masked = Masker.new.mask(@draft.body) if @draft
  end

  def resolve
    return redirect_to(@req, alert: "まだ済んでいないやることがあります") unless @req.all_done? || params[:force] == "1"

    @req.update!(status: "resolved", resolved_on: Date.current)
    Audit.label!("依頼「#{@req.title}」を解決にした")
    redirect_to @req, notice: "依頼を解決にしました(元に戻せます)"
  end

  def cover_letter
    return redirect_to(@req, alert: "AI の鍵(ANTHROPIC_API_KEY)が設定されていません") unless Bookkeeper::Client.configured?

    Requests::CoverLetter.new(@req).call
    redirect_to incoming_request_path(@req, anchor: "cover"), notice: "送付状の下書きを作りました。直してから使ってください"
  rescue Bookkeeper::Client::Error => e
    redirect_to @req, alert: "下書きを作れませんでした(#{e.message})"
  end

  private

  def set_request = @req = IncomingRequest.find(params[:id])
end
