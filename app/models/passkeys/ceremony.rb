module Passkeys
  # パスキーを作る(登録)・使う(ログインと本人の確かめ直し)やりとり。チャレンジ(1 回だけ使う乱数)は呼び出し側がセッションに覚える。
  # 署名の検証は webauthn gem が行う。自動テストは WebAuthn::FakeClient で往復を確かめる。
  # 実機(Touch ID・スマホなど)とブラウザの動きは自動テストでは確かめられないので、人と一緒に確かめる(notes の手順)。
  class Ceremony
    class Failed < StandardError; end

    def initialize(relying_party) = @rp = relying_party

    # 登録の申し込み。すでに持っているパスキーは同じ端末で二重に作らないよう除く。
    def registration_options(user)
      user.ensure_webauthn_id!
      @rp.options_for_registration(
        user: { id: user.webauthn_id, name: user.email_address, display_name: user.name.presence || user.email_address },
        exclude: user.passkeys.pluck(:external_id),
        authenticator_selection: { resident_key: "required", user_verification: "required" }
      )
    end

    def register(user, credential:, challenge:, name:)
      verified = @rp.verify_registration(credential, challenge, user_verification: true)
      user.passkeys.create!(external_id: verified.id, public_key: @rp.encoder.encode(verified.public_key),
                            sign_count: verified.sign_count, name: name.to_s.strip.first(60))
    rescue WebAuthn::Error => e
      raise Failed, e.message
    end

    # ログイン(user なし: 端末が持っているパスキーから選ぶ)と、本人の確かめ直し(user あり: その人のパスキーだけ)の申し込み。
    def authentication_options(user: nil)
      @rp.options_for_authentication(allow: user ? user.passkeys.pluck(:external_id) : [], user_verification: "required")
    end

    def authenticate(credential:, challenge:, user: nil)
      passkey = Passkey.find_by(external_id: credential.is_a?(Hash) ? credential["id"] : nil)
      raise Failed, "このパスキーは登録されていません" unless passkey
      raise Failed, "ほかの人のパスキーです" if user && passkey.user_id != user.id

      verified = @rp.verify_authentication(credential, challenge, public_key: @rp.encoder.decode(passkey.public_key),
                                                                  sign_count: passkey.sign_count, user_verification: true)
      # 使った回数と日は、操作履歴には残さない(ログインのたびに履歴が増えるため)
      Audit.without { passkey.update!(sign_count: verified.sign_count, last_used_at: Time.current) }
      passkey
    rescue WebAuthn::Error => e
      raise Failed, e.message
    end
  end
end
