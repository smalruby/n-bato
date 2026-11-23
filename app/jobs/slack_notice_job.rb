# 1 時間ごとに、Slack へ期限のリマインドと記録の知らせを送る(見直し第10回)。止まっていた間の分は、次に動いたときにまとめて送る。
class SlackNoticeJob < ApplicationJob
  def perform
    return unless SlackNotice.configured?

    SlackNotice::Digest.new.run!
    SlackNotice::Activity.new.run!
  end
end
