# 依頼の対話の発言。下書き → 伏せた文を人が確かめる → AI に送る → AI の案を人が「決める」。
# 送る・決めるは IncomingRequestMessages::DeliveriesController・AdoptionsController(docs/adr/0034)。
class IncomingRequestMessagesController < ApplicationController
  undoable_screen
  before_action :set_request

  def create
    text = params[:body].to_s.strip
    return redirect_to(incoming_request_path(@req, anchor: "draft"), alert: "書いてから送ってください") if text.empty?

    IncomingRequestMessage.write!(@req, role: "user", body: text, files: Array(params[:files]).compact_blank)
    redirect_to incoming_request_path(@req, anchor: "draft")
  end

  # 送る前の下書きだけを消す。何も残らない依頼は、依頼ごと消す。
  def destroy
    @req.messages.drafts.find(params[:id]).discard!
    if @req.reload.discardable?
      @req.destroy!
      return redirect_to(todos_path, notice: "下書きを消しました")
    end
    redirect_to @req, notice: "下書きを消しました"
  end

  private

  def set_request = @req = IncomingRequest.find(params[:incoming_request_id])
end
