# パスキーでログインする(見直し第14回)。チャレンジはセッションに覚え、1 回使ったら消す。
class PasskeySessionsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 20, within: 3.minutes, only: :create, with: -> { render json: {ok: false, message: "しばらくしてからもう一度お試しください"}, status: :too_many_requests }

  def options
    opts = ceremony.authentication_options
    session[:passkey_login_challenge] = opts.challenge
    render json: opts
  end

  def create
    passkey = ceremony.authenticate(credential: credential_param, challenge: session.delete(:passkey_login_challenge))
    start_new_session_for passkey.user
    render json: {ok: true, redirect: after_authentication_url}
  rescue Passkeys::Ceremony::Failed
    render json: {ok: false, message: "パスキーでログインできませんでした。もう一度試すか、メールアドレスとパスワードでログインしてください"}, status: :unprocessable_content
  end

  private

  def ceremony = Passkeys::Ceremony.new(Passkeys::RelyingParty.for(host: request.host, origin: request.base_url))
  def credential_param = params.require(:credential).to_unsafe_h
end
