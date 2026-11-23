module Requests
  # AI の案を、人が「決める」を押したときに記録する(操作履歴に残り、元に戻せる)。
  class Applier
    def initialize(message) = @message = message

    def call
      raise ArgumentError, "この案はもう決めてあります" if @message.applied?

      request = @message.incoming_request
      p = @message.proposal || {}
      ActiveRecord::Base.transaction do
        attrs = (p["request"] || {}).slice("title", "counterpart", "received_on", "due_on").reject { |_, v| v.blank? }
        attrs = attrs.to_h { |k, v| [ k, k.end_with?("_on") ? (Date.iso8601(v) rescue nil) : v ] }.compact
        request.update!(attrs) if attrs.any?
        pos = request.todos.maximum(:position).to_i
        created = Array(p["todos_new"]).map do |t|
          request.todos.create!(position: pos += 1, title: t["title"], fiscal_year: t["fiscal_year"].to_i.positive? ? t["fiscal_year"].to_i : nil,
                                kind: t["kind"].presence_in(Todo::KINDS.keys) || "screen", assignee: t["assignee"].to_s,
                                due_on: (Date.iso8601(t["due_on"]) rescue nil), target: t["target"].to_s.presence_in(Todo::TARGETS.keys) || "",
                                done_rule: t["done_rule"].to_s.presence_in(Todo::DONE_RULES.keys) || "", note: t["note"].to_s)
        end
        updated = Array(p["todos_update"]).filter_map do |u|
          todo = request.todos.find_by(id: u["id"]) or next
          st = u["status"].presence_in(Todo::STATUSES.keys) or next
          todo.update!(status: st, waiting_on: st == "wait" ? u["waiting_on"].to_s : "",
                       done_at: st == "done" ? Time.current : nil, done_by: st == "done" ? "user" : "", done_note: st == "done" ? u["done_note"].to_s : "")
          todo
        end
        @message.update!(applied_at: Time.current)
        Audit.label!("依頼「#{request.title}」: AI の案で、やることを #{created.size} 件作り、#{updated.size} 件直した")
        [ created, updated ]
      end
    end
  end
end
