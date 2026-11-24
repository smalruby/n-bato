# 架空のデータ: やることと依頼(issue #14)。
# やること・依頼はイミュータブルデータモデル(ADR-0034)なので、状態はイベントの入口で変える
# (Todo::StatusChange.change!・IncomingRequestMessage.write!・IncomingRequestMessage::Delivery.deliver!)。
module Demo
  module Todos
    module_function

    def build!(year:, today:)
      request = IncomingRequest.create!(
        title: "架空市から: 事業報告書の記載の確認", counterpart: "架空市 市民協働課(架空)",
        received_on: today - 10, due_on: today + 20
      )
      asked = IncomingRequestMessage.write!(request, role: "user", at: (today - 10).beginning_of_day + 9.hours,
        body: "架空市から、#{year - 1}年度の事業報告書の会員数の書き方について確認の連絡が来た。")
      IncomingRequestMessage::Delivery.deliver!(
        asked, masked_body: "{所轄庁}から、#{year - 1}年度の事業報告書の会員数の書き方について確認の連絡が来た。",
        send_attachments: false, at: (today - 10).beginning_of_day + 9.hours + 1.minute,
        reply: {"reply" => "会員数の数え方を確かめて、架空市へ返事をしましょう(架空の AI の返事)。"}
      )
      counting = request.todos.create!(title: "会員数の数え方を確かめる", fiscal_year: year - 1, kind: "screen", assignee: "事務局",
        due_on: today + 7, target: "people", position: 0)
      Todo::StatusChange.change!(counting, status: "doing", by: nil, at: (today - 9).beginning_of_day + 10.hours)
      request.todos.create!(title: "架空市へ返事をする", fiscal_year: year - 1, kind: "window", assignee: "理事長",
        due_on: today + 20, position: 1)

      Todo.create!(title: "#{year - 1}年度の事業報告書等を出す", fiscal_year: year - 1, kind: "document", assignee: "理事長",
        due_on: Date.new(year, 6, 30), target: "annual_reports", done_rule: "annual_report_submitted")
      waiting = Todo.create!(title: "法務局の補正の連絡を待つ", kind: "window", assignee: "理事長",
        target: "registrations", resume_rule: "registration_completed")
      Todo::StatusChange.change!(waiting, status: "wait", waiting_on: "法務局(架空)", by: nil, at: (today - 4).beginning_of_day + 10.hours)
      Todo.create!(title: "通帳の残高を確かめる", fiscal_year: year, kind: "screen", assignee: "会計",
        due_on: today - 3, target: "balance_checks")
      receipts = Todo.create!(title: "会費の領収書を配る", fiscal_year: year, kind: "ask", assignee: "事務局")
      Todo::StatusChange.change!(receipts, status: "done", note: "総会で配った", by: nil, at: today.beginning_of_day - 5.days)
    end
  end
end
