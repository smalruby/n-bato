require "test_helper"

class PasskeysRelyingPartyTest < ActiveSupport::TestCase
  test "ふつうはリクエストのホスト。環境変数があればそれを使う(ドメインごとに分ける)" do
    rp = Passkeys::RelyingParty.for(host: "localhost", origin: "http://localhost:3200", env: {})
    assert_equal "localhost", rp.id
    assert_equal [ "http://localhost:3200" ], rp.allowed_origins

    rp = Passkeys::RelyingParty.for(host: "web", origin: "http://web", env: { "WEBAUTHN_RP_ID" => "n-bato.example.org", "WEBAUTHN_ORIGIN" => "https://n-bato.example.org" })
    assert_equal "n-bato.example.org", rp.id
    assert_equal [ "https://n-bato.example.org" ], rp.allowed_origins
  end

  test "本人の確かめ直し: 最後に確かめてから 10 分まで" do
    s = users(:one).sessions.create!(created_at: Time.current)
    assert s.verified_recently?
    assert_not s.verified_recently?(11.minutes.from_now)
    s.verified!(20.minutes.from_now)
    assert s.verified_recently?(25.minutes.from_now)
  end

  test "パスキーで使う値は乱数で、1 回作ったら変えない" do
    u = users(:one)
    id = u.ensure_webauthn_id!
    assert id.present?
    assert_not_includes id, u.email_address
    assert_equal id, u.reload.ensure_webauthn_id!
    assert_equal "名前のないパスキー", Passkey.new.display_name
  end
end
