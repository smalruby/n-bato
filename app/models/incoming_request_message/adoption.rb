# AI の案を、人が「この案で決める」で決めた(イベント。日時は adopted_at)。docs/adr/0034
# 案のとおりに、依頼の題・相手・届いた日・期限を直し、やることを作り、やることの状態を変える(Todo::StatusChange)。
# ふつうの操作なので、元に戻せる(元に戻すと、作ったやることも、このイベントも消える)。
class IncomingRequestMessage::Adoption < ApplicationRecord
  include EventRecord
  event_of :adopted_at, entry: :adopt!

  belongs_to :message, class_name: "IncomingRequestMessage", inverse_of: :adoption
  belongs_to :adopted_by, class_name: "User", optional: true

  def self.model_name_label = "AI の案を決めた"

  # やることを作った数と直した数を [作ったもの, 直したもの] で返す
  def self.adopt!(message, by: Current.user, at: Time.current)
    raise ArgumentError, "この案はもう決めてあります" if message.applied?
    raise ArgumentError, "AI の案ではありません" if message.user?

    request = message.incoming_request
    p = message.proposal || {}
    Audit.operation do
      transaction do
        attrs = (p["request"] || {}).slice("title", "counterpart", "received_on", "due_on").reject { |_, v| v.blank? }
        attrs = attrs.to_h { |k, v| [ k, k.end_with?("_on") ? (Date.iso8601(v) rescue nil) : v ] }.compact
        request.update!(attrs) if attrs.any?
        created = create_todos(request, p["todos_new"])
        updated = Array(p["todos_update"]).filter_map do |u|
          todo = request.todos.find_by(id: u["id"]) or next
          status = u["status"].presence_in(Todo::STATUSES.keys) or next
          Todo::StatusChange.change!(todo, status:, waiting_on: u["waiting_on"].to_s, note: u["done_note"].to_s, by:, at:)
          todo
        end
        create!(message:, adopted_by: by, adopted_at: at)
        Audit.label!("依頼「#{request.title}」: AI の案で、やることを #{created.size} 件作り、#{updated.size} 件直した")
        [ created, updated ]
      end
    end
  end

  def self.create_todos(request, list)
    pos = request.todos.maximum(:position).to_i
    Array(list).map do |t|
      request.todos.create!(position: pos += 1, title: t["title"], fiscal_year: t["fiscal_year"].to_i.positive? ? t["fiscal_year"].to_i : nil,
                            kind: t["kind"].presence_in(Todo::KINDS.keys) || "screen", assignee: t["assignee"].to_s,
                            due_on: (Date.iso8601(t["due_on"]) rescue nil), target: t["target"].to_s.presence_in(Todo::TARGETS.keys) || "",
                            done_rule: t["done_rule"].to_s.presence_in(Todo::DONE_RULES.keys) || "", note: t["note"].to_s)
    end
  end
  private_class_method :create_todos
end
