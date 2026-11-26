# 読み込んでよいところの決まり(CSP。#58)。
# もし画面に文を差し込まれても、スクリプトを動かされないようにする。外のサイトからは何も読み込まない(importmap も自分のサイト)。
# スクリプトは自分のサイトのものと、nonce の付いたもの(importmap の script)だけ。
# style 属性は画面にたくさんあるので、スタイルだけは書いた場所のものも許す(スタイルではスクリプトは動かない)
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    policy.style_src :self, :unsafe_inline
    policy.img_src :self, :data, :blob
    policy.font_src :self, :data
    policy.connect_src :self
    policy.object_src :none
    policy.base_uri :self
    policy.form_action :self
    policy.frame_ancestors :none
  end

  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_nonce_auto = true
end
