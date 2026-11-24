# Slack とつながるかを、人と一緒に 1 段ずつ確かめる(アプリには組み込まない。n-bato のデータベースにも触れない)。
#   ruby script/slack_check.rb ~/.private/n-bato-slack.env auth      … 鍵とチャンネルを確かめる(何も送らない)
#   ruby script/slack_check.rb ~/.private/n-bato-slack.env preview   … 送る試しの文を見せる(送らない)
#   ruby script/slack_check.rb ~/.private/n-bato-slack.env send      … 試しの文を 1 件送る
#   ruby script/slack_check.rb ~/.private/n-bato-slack.env listen    … Socket Mode でつなぎ、ショートカットを 1 件受け取って中身の形だけ出す
# 鍵(トークン)の値は表示しない。
require "net/http"
require "json"
require "uri"
require "openssl"
require "socket"

env_file, step = ARGV
abort "使い方: ruby script/slack_check.rb <env ファイル> auth|preview|send|listen" unless env_file && step
ENVS = File.readlines(File.expand_path(env_file), chomp: true).reject { it.strip.empty? || it.start_with?("#") }
  .to_h { it.split("=", 2).map(&:strip) }.transform_values { it.delete_prefix('"').delete_suffix('"') }
BOT = ENVS.fetch("SLACK_BOT_TOKEN")
APP = ENVS["SLACK_APP_TOKEN"]
CHANNEL = ENVS["SLACK_CHANNEL_ID"] || ENVS.fetch("SLACK_OFFICERS_CHANNEL_ID")

def api(method, token: BOT, params: nil, json: nil)
  uri = URI("https://slack.com/api/#{method}")
  uri.query = URI.encode_www_form(params) if params
  req = if json
    Net::HTTP::Post.new(uri, "Content-Type" => "application/json; charset=utf-8")
  else
    ((method == "apps.connections.open") ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri))
  end
  req["Authorization"] = "Bearer #{token}"
  req.body = json.to_json if json
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) { it.request(req) }
  JSON.parse(res.body).merge("_scopes" => res["x-oauth-scopes"])
end

TEXT = "*Nばと(試し)* Slack とつながるかの確かめです。この知らせは Nばと から送りました。返信は要りません。"

case step
when "auth"
  a = api("auth.test")
  puts "ボットの鍵: #{a["ok"] ? "OK" : "だめ(#{a["error"]})"}  ワークスペース: #{a["team"]}  ボット名: #{a["user"]}"
  puts "ボットの権限: #{a["_scopes"]}"
  c = api("conversations.info", params: {channel: CHANNEL})
  if c["ok"]
    ch = c["channel"]
    puts "チャンネル: ##{ch["name"]}  非公開: #{ch["is_private"] ? "はい" : "いいえ"}  ボットが入っている: #{ch["is_member"] ? "はい" : "いいえ(招待が要る)"}  人数: #{ch["num_members"] || "不明"}"
  else
    puts "チャンネル: 確かめられない(#{c["error"]})#{"。非公開チャンネルはボットを招待し、groups:read の権限が要ります" if c["error"] == "missing_scope" || c["error"] == "channel_not_found"}"
  end
  if APP
    o = api("apps.connections.open", token: APP)
    puts "Socket Mode の鍵: #{o["ok"] ? "OK(つなげます)" : "だめ(#{o["error"]})"}"
  else
    puts "Socket Mode の鍵(SLACK_APP_TOKEN): ありません"
  end
when "preview"
  puts "送り先のチャンネル ID: #{CHANNEL}", "送る文:", TEXT
when "send"
  r = api("chat.postMessage", json: {channel: CHANNEL, text: TEXT, unfurl_links: false})
  puts r["ok"] ? "送りました(#{r["ts"]})。Slack で見えるか確かめてください。" : "送れませんでした(#{r["error"]})"
when "listen"
  require "websocket/driver"
  o = api("apps.connections.open", token: APP.to_s)
  abort "Socket Mode でつなげません(#{o["error"]})" unless o["ok"]
  url = URI(o["url"])
  tcp = TCPSocket.new(url.host, 443)
  ssl = OpenSSL::SSL::SSLSocket.new(tcp, OpenSSL::SSL::SSLContext.new.tap { it.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER) })
  ssl.hostname = url.host
  ssl.sync_close = true
  ssl.connect
  io = Struct.new(:url, :sock) { def write(d) = sock.write(d) }.new(o["url"], ssl)
  driver = WebSocket::Driver.client(io)
  done = false
  driver.on(:open) { puts "つなぎました。Slack でメッセージのメニュー「Nばとのやることにする」を選んでください(2 分待ちます)。" }
  driver.on(:message) do |e|
    msg = JSON.parse(e.data)
    driver.text({envelope_id: msg["envelope_id"]}.to_json) if msg["envelope_id"] # 受け取ったことを Slack に返す(3 秒以内)
    case msg["type"]
    when "hello" then nil
    when "disconnect" then puts "Slack から切られました(#{msg.dig("reason")})"
                           done = true
    when "interactive"
      p = msg["payload"]
      m = p["message"] || {}
      puts "受け取りました: 種類 #{p["type"]} / callback_id #{p["callback_id"]} / 選んだ人 #{p.dig("user", "name")} / チャンネル #{p.dig("channel", "name")}"
      puts "  メッセージの文: #{m["text"].to_s.size} 字(中身は出しません) / 添付 #{Array(m["files"]).size} 件 #{Array(m["files"]).map { it["mimetype"] }.join(", ")}"
      done = true
    else
      puts "受け取りました: #{msg["type"]}"
    end
  end
  driver.on(:close) { |e|
    puts "切れました(#{e.code})"
    done = true
  }
  driver.start
  deadline = Time.now + 120
  until done || Time.now > deadline
    next unless IO.select([ssl], nil, nil, 1)

    driver.parse(ssl.read_nonblock(65_536, exception: false).then { (it == :wait_readable) ? "" : it.to_s })
  end
  puts "2 分たちました。受け取れませんでした。" unless done
  driver.close
  ssl.close
else
  abort "auth|preview|send|listen のどれかを指定してください"
end
