# 外から届いた依頼と、依頼ごとの AI との対話(デザインシステム「やること」の RequestThread)。
# 解決にする・送付状の下書きは IncomingRequests::SettlementsController・CoverLettersController(docs/adr/0034)。
class IncomingRequestsController < ApplicationController
  undoable_screen
  before_action :set_request, only: %i[show]

  def new; end

  # 依頼を作り、最初の発言(メール本文と添付)を下書きとして置く。AI にはまだ送らない(伏せた文を人が確かめてから)。
  def create
    text = params[:body].to_s.strip
    return redirect_to(new_incoming_request_path, alert: "依頼の文(メールの本文など)を貼ってください") if text.empty?

    req = IncomingRequest.create!
    IncomingRequestMessage.write!(req, role: "user", body: text, files: Array(params[:files]).compact_blank)
    redirect_to incoming_request_path(req, anchor: "draft")
  end

  def show
    Todo.refresh_auto!
    @draft = @req.messages.drafts.last
    @masked = Masker.new.mask(@draft.body) if @draft
  end

  private

  def set_request = @req = IncomingRequest.find(params[:id])
end
