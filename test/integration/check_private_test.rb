require "test_helper"
require "open3"

# bin/check-private の許可の一覧(config/check_private_allow.yml)が広すぎて、本物らしい情報を見逃さないこと(PR #19 の B3)。
# 試しの文は、このファイル自身が点検に引っかからないよう、全角スペース("\u3000")や番地を実行時に組み立てる
class CheckPrivateTest < ActiveSupport::TestCase
  SP = "\u3000"
  NUM = "1-2-3"

  test "架空の氏名と住所は db/demo の中で許される" do
    out, ok = check(%(name: "見本#{SP}一郎", address: "架空市見本町#{NUM}"), "db/demo/seed.rb")
    assert ok, out
  end

  test "架空の氏名のあとに続く、本物らしい氏名は見逃さない" do
    [ %(["架空#{SP}花子","本田#{SP}宗一"]), %(架空#{SP}花子#{SP}本田#{SP}宗一), %(見本#{SP}一郎 本田#{SP}宗一 理事) ].each do |text|
      out, ok = check(text, "db/demo/seed.rb")
      assert_not ok, "見逃した: #{text}"
      assert_includes out, "氏名"
    end
  end

  test "架空の氏でも、種で使っていない名は許さない" do
    _, ok = check(%(架空#{SP}宗一), "db/demo/seed.rb")
    assert_not ok
  end

  test "架空市の住所のあとに続く、本物らしい住所は見逃さない" do
    out, ok = check(%(架空市見本町#{NUM}"、"本田市中町#{NUM}), "db/demo/seed.rb")
    assert_not ok
    assert_includes out, "住所"
  end

  test "test/system では架空の氏名も許さない(許すのは db/demo だけ)" do
    _, ok = check(%(見本#{SP}一郎), "test/system/demo_screens_test.rb")
    assert_not ok
  end

  private

  def check(text, path)
    out, status = Open3.capture2e({ "CI" => "1" }, Rails.root.join("bin/check-private").to_s, "--text", path, stdin_data: "#{text}\n")
    [ out, status.success? ]
  end
end
