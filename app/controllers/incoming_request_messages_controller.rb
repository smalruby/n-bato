# 依頼の対話の発言。下書き → 伏せた文を人が確かめる → AI に送る → AI の案を人が「決める」。
class IncomingRequestMessagesController < ApplicationController
  undoable_screen
  before_action :set_request

  def create
    text = params[:body].to_s.strip
    return redirect_to(incoming_request_path(@req, anchor: "draft"), alert: "書いてから送ってください") if text.empty?

    IncomingRequestMessages.draft!(@req, text, Array(params[:files]).compact_blank)
    redirect_to incoming_request_path(@req, anchor: "draft")
  end

  # 伏せた文(と、人が選んだときだけ添付)を AI に送る
  def deliver
    msg = @req.messages.find(params[:message_id])
    return redirect_to(@req, alert: "AI の鍵(ANTHROPIC_API_KEY)が設定されていません") unless Bookkeeper::Client.configured?

    msg.update!(masked_body: Masker.new.mask(msg.body).text, send_attachments: params[:send_attachments] == "1")
    Requests::Organizer.new(@req).call(msg)
    redirect_to incoming_request_path(@req, anchor: "thread-end")
  rescue Bookkeeper::Client::Error => e
    redirect_to incoming_request_path(@req, anchor: "draft"), alert: "AI に送れませんでした(#{e.message})"
  end

  def apply
    msg = @req.messages.find(params[:message_id])
    created, updated = Requests::Applier.new(msg).call
    redirect_to incoming_request_path(@req, anchor: "todos"), notice: "やることを #{created.size} 件作り、#{updated.size} 件直しました(元に戻せます)"
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to @req, alert: e.message
  end

  def destroy
    msg = @req.messages.where(sent_at: nil, role: "user").find(params[:id])
    msg.destroy!
    if @req.messages.reload.none? && @req.todos.none?
      @req.destroy!
      return redirect_to(todos_path, notice: "下書きを消しました")
    end
    redirect_to @req, notice: "下書きを消しました"
  end

  private

  def set_request = @req = IncomingRequest.find(params[:incoming_request_id])
end
