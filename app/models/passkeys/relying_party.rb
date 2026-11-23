module Passkeys
  # パスキーを結びつけるサイト(WebAuthn の Relying Party)。見直し第14回: ドメインごとに分ける(親のドメインで共有しない)。
  # ふつうはリクエストのホスト(手元 localhost、本番・ステージングはそれぞれのドメイン)。
  # 環境変数 WEBAUTHN_RP_ID / WEBAUTHN_ORIGIN があればそれを使う(プロキシの後ろなどで、ホストが変わって見えるとき)。
  module RelyingParty
    NAME = "Nばと"

    def self.for(host:, origin:, env: ENV)
      WebAuthn::RelyingParty.new(
        id: env["WEBAUTHN_RP_ID"].presence || host,
        allowed_origins: [ env["WEBAUTHN_ORIGIN"].presence || origin ],
        name: NAME
      )
    end
  end
end
