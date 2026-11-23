require "test_helper"

# パスワードを忘れたとき(デザインシステム SignIn と同じ枠)
class PasswordsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "忘れたとき: 日本語の画面で、登録があればリンクを送り、決め直せる" do
    user = users(:one)
    get new_password_path
    assert_select ".nb-signin h1", "パスワードを忘れたとき"

    assert_enqueued_emails(1) { post passwords_path, params: { email_address: user.email_address } }
    assert_redirected_to new_session_path

    get edit_password_path(user.password_reset_token)
    assert_select ".nb-signin h1", "パスワードを決め直す"
    put password_path(user.password_reset_token), params: { password: "new-pass-123", password_confirmation: "new-pass-123" }
    assert_redirected_to new_session_path
    assert user.reload.authenticate("new-pass-123")
  end

  test "登録のないメールアドレスでも同じ案内を出す(登録の有無を明かさない)" do
    assert_no_enqueued_emails { post passwords_path, params: { email_address: "nobody@example.com" } }
    assert_redirected_to new_session_path
  end
end
