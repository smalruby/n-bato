# 依頼を解決にした(イベント。日付は settled_on)。docs/adr/0034
# ふつうは、やることが全部済んでから。force のときは済んでいないものがあっても解決にする。
# ふつうの操作なので、元に戻せる(元に戻すと、このイベントも消え、依頼は進行中に戻る)。
# 名前は Settlement(「決議」の Resolution とぶつからないように)。
class IncomingRequest::Settlement < ApplicationRecord
  include EventRecord
  event_of :settled_on, entry: :settle!

  belongs_to :incoming_request
  belongs_to :settled_by, class_name: "User", optional: true

  def self.model_name_label = "依頼の解決"

  def self.settle!(request, force: false, by: Current.user, on: Date.current)
    raise ArgumentError, "もう解決にしてあります" if request.resolved?
    raise ArgumentError, "まだ済んでいないやることがあります" unless request.all_done? || force

    transaction do
      request.apply_state!(status: "resolved", resolved_on: on)
      settlement = create!(incoming_request: request, settled_by: by, settled_on: on)
      Audit.label!("依頼「#{request.title}」を解決にした")
      settlement
    end
  end
end
