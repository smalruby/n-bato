require "test_helper"
require "open3"
require "tmpdir"

# bin/kamal-secret(.kamal/secrets から呼ぶ。docs/deploy.md): 環境変数があればそれ、無ければ秘密の置き場所のファイル。
# 値は標準出力にだけ出し、エラーには名前しか書かない。値はすべて架空のもの。
class KamalSecretTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("bin/kamal-secret").to_s

  test "同じ名前の環境変数があれば、それを出す(置き場所のファイルより先)" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "anthropic.env"), "ANTHROPIC_API_KEY=from-file\n")
      out, err, ok = run_secret("ANTHROPIC_API_KEY", "ANTHROPIC_API_KEY" => "from-env", "NBATO_SECRETS_DIR" => dir)
      assert ok, err
      assert_equal "from-env", out
    end
  end

  test "環境変数が無ければ、置き場所のファイルの「名前=値」の行から出す" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ses-smtp.env"), "SMTP_USERNAME=user-a\nSMTP_PASSWORD=pass-b\n")
      out, err, ok = run_secret("SMTP_PASSWORD", "NBATO_SECRETS_DIR" => dir)
      assert ok, err
      assert_equal "pass-b", out
    end
  end

  test "鍵のファイルは中身をそのまま出す" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "rails-master.key"), "fake-master")
      out, err, ok = run_secret("RAILS_MASTER_KEY", "NBATO_SECRETS_DIR" => dir)
      assert ok, err
      assert_equal "fake-master", out
    end
  end

  test "ファイルに行が無い・ファイルが無い・置き場所が無いときは、名前だけを書いて失敗する" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "mail.env"), "OTHER=x\n")
      _, err, ok = run_secret("NBATO_MAIL_FROM", "NBATO_SECRETS_DIR" => dir)
      assert_not ok
      assert_includes err, "NBATO_MAIL_FROM= の行がありません"

      _, err, ok = run_secret("ANTHROPIC_API_KEY", "NBATO_SECRETS_DIR" => dir)
      assert_not ok
      assert_includes err, "anthropic.env が読めません"
    end
    _, err, ok = run_secret("ANTHROPIC_API_KEY")
    assert_not ok
    assert_includes err, "NBATO_SECRETS_DIR"
  end

  test "ghcr.io のトークンは環境変数だけ(Mac での持ち方は開発QAボード 第9回の答え待ち)" do
    out, err, ok = run_secret("KAMAL_REGISTRY_PASSWORD", "KAMAL_REGISTRY_PASSWORD" => "job-token")
    assert ok, err
    assert_equal "job-token", out

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ghcr.env"), "KAMAL_REGISTRY_PASSWORD=from-file\n")
      out, err, ok = run_secret("KAMAL_REGISTRY_PASSWORD", "NBATO_SECRETS_DIR" => dir)
      assert_not ok
      assert_empty out
      assert_includes err, "第9回の答え待ち"
    end
  end

  test "知らない名前は失敗する" do
    _, err, ok = run_secret("SOMETHING_ELSE")
    assert_not ok
    assert_includes err, "知らない名前"
  end

  private

  # 手元の環境変数(本物の NBATO_SECRETS_DIR など)を持ち込まない
  def run_secret(name, env = {})
    clean = %w[NBATO_SECRETS_DIR RAILS_MASTER_KEY ANTHROPIC_API_KEY SMTP_USERNAME SMTP_PASSWORD NBATO_MAIL_FROM
      KAMAL_REGISTRY_USERNAME KAMAL_REGISTRY_PASSWORD].to_h { [it, nil] }
    out, err, status = Open3.capture3(clean.merge(env), SCRIPT, name)
    [out, err, status.success?]
  end
end
