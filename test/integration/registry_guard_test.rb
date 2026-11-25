require "test_helper"
require "open3"
require "tmpdir"

# Mac は ghcr.io のトークンを持たない(開発QAボード 第9回 r9-ghcr、docs/deploy.md)ための守り。
# - .kamal/hooks/pre-connect: トークンの要る Kamal の操作(deploy など)を、つなぐ前に止める
# - bin/prod-restore: Actions(Restore)からは名前の入れ直しの代わりに NBATO_RESTORE_CONFIRMED で確かめる
# どちらも本番にはつながない(止まるところだけを確かめる。bin/kamal までは進ませない)。
class RegistryGuardTest < ActiveSupport::TestCase
  HOOK = Rails.root.join(".kamal/hooks/pre-connect").to_s
  RESTORE = Rails.root.join("bin/prod-restore").to_s
  NAME = "production-20260101-000000.sqlite3"

  test "トークンが無いと、deploy・build・registry login は止まり、次にすることを書く" do
    [["deploy", nil], ["redeploy", nil], ["setup", nil], ["build", "push"], ["registry", "login"]].each do |command, sub|
      _, err, ok = run_hook(command, sub)
      assert_not ok, "#{command} #{sub}"
      assert_includes err, "gh workflow run deploy.yml"
      assert_includes err, "docs/deploy.md"
    end
  end

  test "トークンが無くても、--reuse の exec・ロック・ログは止めない(bin/prod-backup・bin/prod-runner)" do
    [["app", "exec"], ["lock", "status"], ["app", "logs"], ["app", "stop"]].each do |command, sub|
      _, err, ok = run_hook(command, sub)
      assert ok, "#{command} #{sub}: #{err}"
    end
  end

  test "トークンがあれば deploy も止めない(Actions・Actions が止まったときの予備)" do
    _, err, ok = run_hook("deploy", nil, "KAMAL_REGISTRY_PASSWORD" => "job-token")
    assert ok, err
  end

  test "bin/prod-restore: 名前の形が違えば止まる" do
    _, err, ok = run_restore("latest.sqlite3", {"GITHUB_ACTIONS" => "true"})
    assert_not ok
    assert_includes err, "名前の形が違う"
  end

  test "bin/prod-restore: NBATO_RESTORE_CONFIRMED が戻す名前と違えば、本番につながずに止まる" do
    _, err, ok = run_restore(NAME, {"GITHUB_ACTIONS" => "true", "NBATO_RESTORE_CONFIRMED" => "production-20260102-000000.sqlite3"})
    assert_not ok
    assert_includes err, "NBATO_RESTORE_CONFIRMED が戻す名前と違う"
  end

  test "bin/prod-restore: Actions でなければ、秘密の置き場所が要る" do
    _, err, ok = run_restore(NAME, {"NBATO_RESTORE_CONFIRMED" => NAME})
    assert_not ok
    assert_includes err, "NBATO_SECRETS_DIR"
  end

  test "bin/prod-restore: 入れ直した名前が違えば止まる(Mac)" do
    Dir.mktmpdir do |dir|
      _, err, ok = run_restore(NAME, {"NBATO_SECRETS_DIR" => dir}, stdin: "production-20260102-000000.sqlite3\n")
      assert_not ok
      assert_includes err, "やめました"
    end
  end

  private

  def run_hook(command, sub, env = {})
    base = {"KAMAL_COMMAND" => command, "KAMAL_SUBCOMMAND" => sub, "KAMAL_REGISTRY_PASSWORD" => nil}
    out, err, status = Open3.capture3(base.merge(env), HOOK)
    [out, err, status.success?]
  end

  # 手元の秘密の置き場所や CI の GITHUB_ACTIONS を持ち込まない
  def run_restore(name, env = {}, stdin: "")
    base = {"NBATO_SECRETS_DIR" => nil, "GITHUB_ACTIONS" => nil, "NBATO_RESTORE_CONFIRMED" => nil}
    out, err, status = Open3.capture3(base.merge(env), RESTORE, name, stdin_data: stdin)
    [out, err, status.success?]
  end
end
