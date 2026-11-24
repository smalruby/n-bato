# 人の発言を AI に送った(イベント。日時は delivered_at)。docs/adr/0034
# 送った伏せた文(masked_body)と、添付を送ったか(send_attachments)を残す。AI の返事(発言)も同じときに書く。
# AI を呼ぶのは Requests::Organizer。返事が来てから、この入口で記録する(AI を待つ間、記録をつかまないように)。
class IncomingRequestMessage::Delivery < ApplicationRecord
  include EventRecord
  event_of :delivered_at, entry: :deliver!

  belongs_to :message, class_name: "IncomingRequestMessage", inverse_of: :delivery

  def self.model_name_label = "依頼の対話を AI に送った"

  # reply: AI の答え(返事 reply と、やることの案)。AI の発言として残す。
  def self.deliver!(message, masked_body:, send_attachments:, reply:, at: Time.current)
    raise ArgumentError, "送る前の下書きではありません" unless message.draft?

    Audit.operation do
      transaction do
        create!(message:, masked_body:, send_attachments:, delivered_at: at)
        IncomingRequestMessage.write!(message.incoming_request, role: "assistant", body: reply.fetch("reply"), proposal: reply)
      end
    end
  end
end
