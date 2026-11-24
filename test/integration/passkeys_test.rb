require "test_helper"
require "webauthn/fake_client"

# パスキー(見直し第14回)。WebAuthn::FakeClient(gem に付いている、ソフトウェアの作り物の端末)で登録とログインの往復を確かめる。
# 実機(Touch ID・スマホ)とブラウザの JavaScript は自動テストでは確かめられないので、人と一緒に確かめる。
class PasskeysTest < ActionDispatch::IntegrationTest
  ORIGIN = "http://www.example.com"

  setup { @client = WebAuthn::FakeClient.new(ORIGIN); ensure_organization }

  def register_passkey(name: "この Mac")
    post registration_options_passkeys_path, as: :json
    assert_response :success
    challenge = response.parsed_body["challenge"]
    post passkeys_path, params: { credential: @client.create(challenge:, user_verified: true), name: }, as: :json
    response.parsed_body
  end

  test "ログインの画面: パスキーでログインを上に、メールアドレスの欄はパスキーの候補も出す" do
    get new_session_path
    assert_response :success
    assert_select ".nb-signin .nb-signin-passkey", text: /パスキーでログイン/
    assert_select ".nb-signin-or", text: /または メールアドレスとパスワード/
    assert_select "input[autocomplete='username webauthn']"
  end

  test "足す → ログアウト → パスキーでログイン(使った日が残り、操作履歴には足したことだけ残る)" do
    sign_in
    body = register_passkey
    assert body["ok"], body.inspect
    pk = users(:one).passkeys.sole
    assert_equal "この Mac", pk.name
    assert_equal "final", AuditOperation.order(:id).last.kind
    assert_match "パスキーを足した", AuditOperation.order(:id).last.label

    get passkeys_path
    assert_select ".nb-passkey-table input[value='この Mac']"

    delete session_path
    post options_passkey_session_path, as: :json
    challenge = response.parsed_body["challenge"]
    ops_before = AuditOperation.count
    post passkey_session_path, params: { credential: @client.get(challenge:, user_verified: true) }, as: :json
    assert response.parsed_body["ok"], response.parsed_body.inspect
    assert pk.reload.last_used_at
    assert_equal ops_before, AuditOperation.count
    get root_path
    assert_response :success
  end

  test "パスキーでのログイン: 登録されていない・チャレンジが無いと失敗する" do
    post passkey_session_path, params: { credential: { id: "nope", type: "public-key" } }, as: :json
    assert_response :unprocessable_entity
    get root_path
    assert_redirected_to new_session_path
  end

  test "ログインから 10 分を過ぎたら、足す・消す前にパスワードで確かめ直す" do
    sign_in
    register_passkey
    pk = users(:one).passkeys.sole
    travel 11.minutes do
      post registration_options_passkeys_path, as: :json
      assert_response :forbidden
      assert_equal "reverify", response.parsed_body["code"]

      get passkeys_path
      assert_select ".nb-passkey-verify"
      delete passkey_path(pk)
      assert_redirected_to passkeys_path
      assert Passkey.exists?(pk.id)

      post verify_password_passkeys_path, params: { password: "wrong" }
      assert_equal "パスワードが違います", flash[:alert]
      post verify_password_passkeys_path, params: { password: "password" }
      assert_match "本人を確かめました", flash[:notice]

      delete passkey_path(pk)
      assert_not Passkey.exists?(pk.id)
      assert_match "パスキーを消した", AuditOperation.order(:id).last.label
    end
  end

  test "パスキーで確かめ直す(自分のパスキーだけ)" do
    sign_in
    register_passkey
    travel 11.minutes do
      post verify_options_passkeys_path, as: :json
      challenge = response.parsed_body["challenge"]
      post verify_passkeys_path, params: { credential: @client.get(challenge:, user_verified: true) }, as: :json
      assert response.parsed_body["ok"], response.parsed_body.inspect
      post registration_options_passkeys_path, as: :json
      assert_response :success
    end

    # ほかの人(users(:two))は、このパスキーで確かめ直せない
    delete session_path
    sign_in users(:two)
    post verify_options_passkeys_path, as: :json
    challenge = response.parsed_body["challenge"]
    post verify_passkeys_path, params: { credential: @client.get(challenge:, user_verified: true) }, as: :json
    assert_response :unprocessable_entity
  end

  test "名前はすぐ保存。ほかの人のパスキーは変えられない" do
    sign_in
    register_passkey
    pk = users(:one).passkeys.sole
    patch passkey_path(pk, format: :json), params: { passkey: { name: "仕事の Mac" } }
    assert response.parsed_body["ok"]
    assert_equal "仕事の Mac", pk.reload.name

    delete session_path
    sign_in users(:two)
    patch passkey_path(pk, format: :json), params: { passkey: { name: "x" } }
    assert_response :not_found
  end

  test "同じ端末で二重に作らない(登録の申し込みで、持っているパスキーを除く)" do
    sign_in
    register_passkey
    post registration_options_passkeys_path, as: :json
    assert_equal [ users(:one).passkeys.sole.external_id ], response.parsed_body["excludeCredentials"].map { it["id"] }
  end

  test "パスキーが登録されていない改ざんした資格情報は足せない" do
    sign_in
    post registration_options_passkeys_path, as: :json
    post passkeys_path, params: { credential: @client.create(challenge: "AAAA", user_verified: true), name: "x" }, as: :json
    assert_response :unprocessable_entity
    assert_equal 0, Passkey.count
  end

  test "チャレンジが違う署名ではログインできない" do
    sign_in
    register_passkey
    delete session_path
    post options_passkey_session_path, as: :json
    post passkey_session_path, params: { credential: @client.get(challenge: "AAAA", user_verified: true) }, as: :json
    assert_response :unprocessable_entity
    get root_path
    assert_redirected_to new_session_path
  end
end
