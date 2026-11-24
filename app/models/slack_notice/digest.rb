module SlackNotice
  # 期限のリマインド: 週 1 回(月曜。止まっていたら、その週の最初に動いたとき)のまとめと、3 日前・当日の知らせ。
  class Digest
    include Rails.application.routes.url_helpers

    def initialize(today: Date.current) = @today = today

    def run!
      items = TodoList.new(helpers: self, today: @today).items.reject(&:done?).select(&:due_on)
      weekly(items)
      items.each { remind(it) }
    end

    private

    def weekly(items)
      near = items.select { it.due_on <= @today + 14 }.sort_by(&:due_on)
      week = @today.beginning_of_week
      text = ["*今週のやること*(#{week.strftime("%-m/%-d")} の週。期限を過ぎたものと、2 週間以内のもの #{near.size} 件)"]
      text += near.first(15).map { line(it) }
      text << "(ほか #{near.size - 15} 件)" if near.size > 15
      text << "期限の近いやることはありません。" if near.empty?
      text << SlackNotice.link("/todos", "やることを開く")
      SlackNotice.post!("weekly-#{week}", text.join("\n"))
    end

    def remind(item)
      days = (item.due_on - @today).to_i
      if days.between?(0, 3) && days != 0
        SlackNotice.post!("due3-#{key(item)}", "*期限まであと #{days} 日* #{line(item)}")
      elsif days <= 0 && days > -7
        SlackNotice.post!("due0-#{key(item)}", "*#{days.zero? ? "今日が期限" : "期限を #{-days} 日過ぎています"}* #{line(item)}")
      end
    end

    def line(item)
      year = item.fiscal_year ? "#{item.fiscal_year}年度 " : ""
      "・#{item.due_on.strftime("%m/%d")} #{year}#{item.title}(#{item.assignee})"
    end

    def key(item) = "#{item.todo ? "todo-#{item.todo.id}" : ::Digest::SHA1.hexdigest(item.title)[0, 12]}-#{item.due_on}"
  end
end
