require "test_helper"

class SlackNoticeJobTest < ActiveJob::TestCase
  setup do
    @sent = []
    SlackNotice.poster = ->(text) {
      @sent << text
      true
    }
    # 知らせることを 1 つ用意する(記録の知らせの続きの位置より後に、年度を始めた操作)
    SlackPost.create!(key: SlackNotice::Activity::CURSOR, text: (AuditOperation.maximum(:id) || 0).to_s)
    Audit.operation(user: nil, scope: "t") { FiscalPeriod.create!(year: 2030) }
  end
  teardown { SlackNotice.poster = nil }

  test "鍵が無ければ何もしない" do
    cursor = SlackPost.find_by!(key: SlackNotice::Activity::CURSOR).text
    with_env("SLACK_BOT_TOKEN" => nil) { SlackNoticeJob.perform_now }
    assert_empty @sent, "送らない"
    assert_equal cursor, SlackPost.find_by!(key: SlackNotice::Activity::CURSOR).text, "続きの位置も進めない(鍵を入れたら送る)"
  end

  test "鍵があれば、期限のリマインドと記録の知らせを見る" do
    with_env("SLACK_BOT_TOKEN" => "xoxb-test", "SLACK_CHANNEL_ID" => "C0TEST") { SlackNoticeJob.perform_now }
    assert @sent.any? { it.include?("2030年度を始めました") }, "記録の知らせを送る"
    assert_equal AuditOperation.maximum(:id).to_s, SlackPost.find_by!(key: SlackNotice::Activity::CURSOR).text, "続きの位置を進める"
  end
end
