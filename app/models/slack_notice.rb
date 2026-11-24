require "net/http"

# Slack への知らせ(見直し第10回)。n-bato から Slack へ送るだけ。Slack から記録は変えない。
# 送り先は、役員だけが入る非公開チャンネル(SLACK_CHANNEL_ID か SLACK_OFFICERS_CHANNEL_ID)。鍵(SLACK_BOT_TOKEN)が無ければ何もしない。
# 組み込む前に人と一緒に確かめる(2026-11-22)。確かめ終わるまで、Docker には鍵を渡さない(script/slack_check.rb で確かめる)。
# 個人情報(住所・電話・メール・名簿・回答の中身・会員の名前)は流さない。
module SlackNotice
  def self.channel_id = ENV["SLACK_CHANNEL_ID"].presence || ENV["SLACK_OFFICERS_CHANNEL_ID"].presence
  def self.configured? = ENV["SLACK_BOT_TOKEN"].present? && channel_id.present?
  def self.base_url = ENV["NBATO_URL"].presence || "http://localhost:3200"

  # 送り方(テストでは差し替える)。戻り値は真偽。
  class << self
    attr_writer :poster
    def poster = @poster ||= method(:chat_post_message)
  end

  # key が同じものは二度送らない
  def self.post!(key, text)
    return false if SlackPost.exists?(key:)
    return false unless configured? || @poster

    ok = poster.call(text)
    SlackPost.create!(key:, text:, posted_at: Time.current) if ok
    ok
  end

  def self.chat_post_message(text, http: Net::HTTP) # http: テストでは偽物を渡す(本物の Slack には送らない)
    uri = URI("https://slack.com/api/chat.postMessage")
    req = Net::HTTP::Post.new(uri, "Authorization" => "Bearer #{ENV.fetch('SLACK_BOT_TOKEN')}", "Content-Type" => "application/json; charset=utf-8")
    req.body = { channel: channel_id, text:, unfurl_links: false }.to_json
    res = http.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 10) { it.request(req) }
    body = JSON.parse(res.body) rescue {}
    Rails.logger.warn("Slack に送れませんでした: #{body['error']}") unless body["ok"]
    body["ok"] == true
  rescue StandardError => e
    Rails.logger.warn("Slack に送れませんでした: #{e.class}: #{e.message}")
    false
  end

  def self.link(path, label = "Nばとで開く") = "<#{base_url}#{path}|#{label}>"
end
