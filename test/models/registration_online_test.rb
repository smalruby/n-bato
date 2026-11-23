require "test_helper"

# 登記・供託オンライン申請システムの使える時間(見直し第20回。config/registration_online.yml)
class RegistrationOnlineTest < ActiveSupport::TestCase
  def at(text) = Time.zone.parse(text)

  test "平日の夜: 使える。法務局の受付は次の平日" do
    s = RegistrationOnline.status(at("2026-11-27 21:00")) # 金曜
    assert s.open
    assert_equal "いまは使えます。今日は 23:00 まで(祝日なら 18:00 まで)", s.message
    assert_equal "いま送ると、11/30(月)の受付になります(祝日なら、その次の平日)。", s.office_message
  end

  test "平日の昼: 今日の受付" do
    s = RegistrationOnline.status(at("2026-11-24 10:00"))
    assert_equal "いま送ると、今日の受付になります(祝日なら次の平日)。", s.office_message
  end

  test "平日の朝: まだ使えない。今日の 8:30 から" do
    s = RegistrationOnline.status(at("2026-11-24 07:00"))
    assert_not s.open
    assert_equal "いまは使えません。次は今日 8:30 から", s.message
    assert_equal "いま送ると、11/24(火)の受付になります(祝日なら、その次の平日)。", s.office_message
  end

  test "土曜の夜: 18:00 まで。次は明日" do
    s = RegistrationOnline.status(at("2026-11-28 19:00"))
    assert_equal "いまは使えません。次は明日 8:30 から", s.message
    assert RegistrationOnline.status(at("2026-11-28 10:00")).message.end_with?("今日は 18:00 まで")
  end

  test "年末年始は使えない" do
    assert_equal "いまは使えません。次は1/4(月) 8:30 から", RegistrationOnline.status(at("2026-12-28 23:30")).message
    assert RegistrationOnline.closed_day?(Date.new(2027, 1, 2))
    assert_not RegistrationOnline.closed_day?(Date.new(2027, 1, 4))
  end

  test "見出しの文" do
    assert_equal "平日 08:30〜23:00 / 休日・祝日 08:30〜18:00(12/29〜1/3 は使えない)", RegistrationOnline.hours_label
    assert_equal "法務局の受付は平日 08:30〜17:15", RegistrationOnline.office_label
    assert_equal "https://www.touki-kyoutaku-online.moj.go.jp/", RegistrationOnline.url
    assert_match "condition", RegistrationOnline.condition_url
  end
end
