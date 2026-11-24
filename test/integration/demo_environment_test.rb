require "test_helper"
require "open3"

# 架空のデータの環境(NBATO_DEMO=1、bin/demo)の起動の設定(PR #19 の B2・B4)。
# development の環境を別のプロセスで起動して確かめる(DB にはつながない)
class DemoEnvironmentTest < ActiveSupport::TestCase
  test "cookie の署名の鍵が、実データの開発サーバ(tmp/local_secret.txt)と別で、鍵の環境変数も消える" do
    script = 'print [Rails.application.secret_key_base, ENV["ANTHROPIC_API_KEY"].inspect, ENV["SLACK_BOT_TOKEN"].inspect].join("\n")'
    env = { "NBATO_DEMO" => "1", "RAILS_ENV" => "development", "ANTHROPIC_API_KEY" => "dummy-for-test", "SLACK_BOT_TOKEN" => "dummy-for-test" }
    out, err, status = Open3.capture3(env, Rails.root.join("bin/rails").to_s, "runner", script, chdir: Rails.root.to_s)
    assert status.success?, err
    demo_secret, anthropic, slack = out.lines.map(&:chomp).last(3)

    assert_operator demo_secret.size, :>=, 64
    assert_equal Rails.root.join("tmp/demo_secret").read.strip, demo_secret
    assert_not_equal Rails.application.secret_key_base, demo_secret # tmp/local_secret.txt(無ければここで作られる)
    assert_not_equal Rails.root.join("tmp/local_secret.txt").read.strip, demo_secret
    assert_equal "nil", anthropic
    assert_equal "nil", slack
  end
end
