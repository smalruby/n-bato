require "test_helper"

# 待つ表示(デザインシステム「待つ表示」): AI の提案を待つ証憑は、残りの秒数を出して自動で読み込み直す
class VoucherWaitingTest < ActionDispatch::IntegrationTest
  setup { sign_in }

  test "提案を待っている証憑は、15 秒ごとに読み込み直す表示を出し、待っていなければ出さない" do
    v = Voucher.create!(kind: "receipt", description: "テストの証憑", status: "proposing")
    get voucher_path(v)
    assert_select ".nb-waiting[data-controller=auto-reload][data-auto-reload-seconds-value='15']"
    assert_select ".nb-waiting [data-auto-reload-target=count]", "15"

    v.update!(status: "pending")
    get voucher_path(v)
    assert_select ".nb-waiting", 0
  end
end
