require "test_helper"

# 公開しているサーバーの、ログインの外から届く口の守り(#58)
class PublicSurfaceTest < ActionDispatch::IntegrationTest
  test "画面に CSP が付き、スクリプトは自分のサイトと nonce の付いたものだけ" do
    get new_session_path
    csp = response.headers["Content-Security-Policy"]
    assert_match(/script-src 'self' 'nonce-[^']+'/, csp)
    assert_match "object-src 'none'", csp
    assert_match "frame-ancestors 'none'", csp
    assert_match "base-uri 'self'", csp
    nonce = csp[/'nonce-([^']+)'/, 1]
    assert_select "script[type=importmap][nonce=?]", nonce
  end

  test "使っていない部品(Action Mailbox・Action Text)を読み込まない" do
    assert_not defined?(ActionMailbox)
    assert_not defined?(ActionText)
    paths = Rails.application.routes.routes.map { it.path.spec.to_s }
    assert_empty paths.grep(%r{/rails/(action_mailbox|conductor|active_storage)})
  end

  test "検索エンジンには載せない" do
    assert_match(/^Disallow: \/$/, Rails.public_path.join("robots.txt").read)
  end

  test "パスワードの再設定のメールは、短い間に何度も送らせない" do
    counting_rate_limit do
      5.times do
        post passwords_path, params: {email_address: users(:one).email_address}
        assert_redirected_to new_session_path
      end
      post passwords_path, params: {email_address: users(:one).email_address}
      assert_redirected_to new_password_path
      assert_equal "しばらくしてからもう一度お試しください", flash[:alert]
    end
  end

  test "パスワードの決め直しも、短い間に何度も試させない" do
    counting_rate_limit do
      10.times { patch password_path("bad-token"), params: {password: "x", password_confirmation: "x"} }
      patch password_path("bad-token"), params: {password: "x", password_confirmation: "x"}
      assert_redirected_to new_password_path
      assert_equal "しばらくしてからもう一度お試しください", flash[:alert]
    end
  end

  private

  # テストのキャッシュは数えない(null_store)ので、回数の制限を確かめる間だけ数える
  def counting_rate_limit
    count = 0
    Rails.cache.define_singleton_method(:increment) { |*, **| count += 1 }
    yield
  ensure
    Rails.cache.singleton_class.remove_method(:increment)
  end
end
