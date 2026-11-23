require "test_helper"

# Slack への知らせ(見直し第10回)。送り方は差し替え、送った文を確かめる。
class SlackNoticeTest < ActiveSupport::TestCase
  setup do
    @sent = []
    SlackNotice.poster = ->(text) { @sent << text; true }
    [ 2023, 2024, 2025, 2026 ].each { FiscalPeriod.find_or_create_by!(year: it) }
  end
  teardown { SlackNotice.poster = nil }

  test "期限のリマインド: 週のまとめ・3 日前・当日を、二度は送らない" do
    req = IncomingRequest.create!(title: "依頼")
    req.todos.create!(title: "3日後の作業", kind: "ask", assignee: "理事長", due_on: Date.new(2026, 11, 26))
    req.todos.create!(title: "今日の作業", kind: "ask", assignee: "理事長", due_on: Date.new(2026, 11, 23))
    SlackNotice::Digest.new(today: Date.new(2026, 11, 23)).run!
    assert @sent.any? { it.include?("今週のやること") && it.include?("3日後の作業") }
    assert @sent.any? { it.include?("期限まであと 3 日") }
    assert @sent.any? { it.include?("今日が期限") && it.include?("今日の作業") }
    n = @sent.size
    SlackNotice::Digest.new(today: Date.new(2026, 11, 23)).run!
    assert_equal n, @sent.size
  end

  test "締めた年度の変更は理由つきで送り、会員の記録は値を出さない" do
    SlackNotice::Activity.new.run!   # 続きの位置を決める
    Audit.operation(user: nil, scope: "t") do
      Audit.reason!("領収書と照合して直した")
      Person.create!(name: "会員 太郎", address: "テスト市1-2-3")
    end
    SlackNotice::Activity.new.run!
    msg = @sent.find { it.include?("締めた年度の変更") }
    assert msg
    assert_includes msg, "理由: 領収書と照合して直した"
    assert_no_match(/テスト市|会員 太郎/, msg)
  end

  test "年度を締めたら知らせる" do
    SlackNotice::Activity.new.run!
    Audit.operation(user: nil, scope: "t") { FiscalPeriod.find_by(year: 2023).update!(closed_at: Time.current) }
    SlackNotice::Activity.new.run!
    assert @sent.any? { it.include?("2023年度を締めました") }
  end
end
