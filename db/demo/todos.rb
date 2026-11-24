# 架空のデータ: やることと依頼(issue #14)。
# Todo・IncomingRequest は作り替えの途中(issue #15)なので、ここだけ直せば済むように、ほかの種から分けておく。
module Demo
  module Todos
    module_function

    def build!(year:, today:)
      request = IncomingRequest.create!(
        title: "架空市から: 事業報告書の記載の確認", counterpart: "架空市 市民協働課(架空)",
        received_on: today - 10, due_on: today + 20
      )
      request.messages.create!(role: "user", body: "架空市から、#{year - 1}年度の事業報告書の会員数の書き方について確認の連絡が来た。",
                               masked_body: "{所轄庁}から、#{year - 1}年度の事業報告書の会員数の書き方について確認の連絡が来た。", sent_at: today - 10)
      request.todos.create!(title: "会員数の数え方を確かめる", fiscal_year: year - 1, kind: "screen", assignee: "事務局", status: "doing",
                            due_on: today + 7, target: "people", position: 0)
      request.todos.create!(title: "架空市へ返事をする", fiscal_year: year - 1, kind: "window", assignee: "理事長", status: "todo",
                            due_on: today + 20, position: 1)

      Todo.create!(title: "#{year - 1}年度の事業報告書等を出す", fiscal_year: year - 1, kind: "document", assignee: "理事長",
                   status: "todo", due_on: Date.new(year, 6, 30), target: "annual_reports", done_rule: "annual_report_submitted")
      Todo.create!(title: "法務局の補正の連絡を待つ", kind: "window", assignee: "理事長", status: "wait", waiting_on: "法務局(架空)",
                   target: "registrations", resume_rule: "registration_completed")
      Todo.create!(title: "通帳の残高を確かめる", fiscal_year: year, kind: "screen", assignee: "会計", status: "todo",
                   due_on: today - 3, target: "balance_checks")
      Todo.create!(title: "会費の領収書を配る", fiscal_year: year, kind: "ask", assignee: "事務局", status: "done",
                   done_at: today.beginning_of_day - 5.days, done_by: "人", done_note: "総会で配った")
    end
  end
end
