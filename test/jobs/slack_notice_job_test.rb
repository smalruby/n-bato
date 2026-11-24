require "test_helper"

class SlackNoticeJobTest < ActiveJob::TestCase
  setup do
    @sent = []
    SlackNotice.poster = ->(text) { @sent << text; true }
  end
  teardown { SlackNotice.poster = nil }

  test "鍵が無ければ何もしない" do
    with_env("SLACK_BOT_TOKEN" => nil) { SlackNoticeJob.perform_now }
    assert_not SlackPost.exists?(key: SlackNotice::Activity::CURSOR)
  end

  test "鍵があれば、期限のリマインドと記録の知らせを見る" do
    with_env("SLACK_BOT_TOKEN" => "xoxb-test", "SLACK_CHANNEL_ID" => "C0TEST") { SlackNoticeJob.perform_now }
    assert SlackPost.exists?(key: SlackNotice::Activity::CURSOR), "記録の知らせの続きの位置を覚える"
  end
end
