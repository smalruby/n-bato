# ログインのしかた(デザインシステム PasskeyList、見直し第14回)。パスキーの一覧・足す・名前を変える・消す。
# 足す・消すは、ログイン(または最後の確かめ直し)から 10 分以内に限る。過ぎていたらパスワードかパスキーで確かめ直す。
class PasskeysController < ApplicationController
  include AutosaveResponse

  rate_limit to: 10, within: 3.minutes, only: %i[verify_password verify], with: -> { redirect_to passkeys_path, alert: "しばらくしてからもう一度お試しください" }
  before_action :require_recent_verification, only: %i[registration_options create destroy]

  def index
    @passkeys = Current.user.passkeys.ordered
    @verified = Current.session.verified_recently?
  end

  def registration_options
    opts = ceremony.registration_options(Current.user)
    session[:passkey_registration_challenge] = opts.challenge
    render json: opts
  end

  def create
    passkey = ceremony.register(Current.user, credential: credential_param, challenge: session.delete(:passkey_registration_challenge), name: params[:name])
    Audit.final!("パスキーを足した: #{passkey.display_name}")
    render json: {ok: true, redirect: passkeys_path}
  rescue Passkeys::Ceremony::Failed
    render json: {ok: false, message: "パスキーを足せませんでした。もう一度試してください"}, status: :unprocessable_content
  end

  def update
    passkey = Current.user.passkeys.find(params[:id])
    passkey.update(name: params.dig(:passkey, :name).to_s.strip)
    Audit.label!("パスキーの名前を変えた: #{passkey.display_name}")
    autosave_response(passkey)
  end

  def destroy
    passkey = Current.user.passkeys.find(params[:id])
    passkey.destroy!
    Audit.final!("パスキーを消した: #{passkey.display_name}")
    redirect_to passkeys_path, notice: "パスキー「#{passkey.display_name}」を消しました"
  end

  # 本人の確かめ直し(パスワード)
  def verify_password
    if Current.user.authenticate(params[:password].to_s)
      Current.session.verified!
      redirect_to passkeys_path, notice: "本人を確かめました。10 分の間、パスキーを足す・消すことができます"
    else
      redirect_to passkeys_path, alert: "パスワードが違います"
    end
  end

  # 本人の確かめ直し(いま持っているパスキー)
  def verify_options
    opts = ceremony.authentication_options(user: Current.user)
    session[:passkey_verify_challenge] = opts.challenge
    render json: opts
  end

  def verify
    ceremony.authenticate(credential: credential_param, challenge: session.delete(:passkey_verify_challenge), user: Current.user)
    Current.session.verified!
    render json: {ok: true, redirect: passkeys_path}
  rescue Passkeys::Ceremony::Failed
    render json: {ok: false, message: "パスキーで確かめられませんでした。パスワードで確かめてください"}, status: :unprocessable_content
  end

  private

  def ceremony = Passkeys::Ceremony.new(Passkeys::RelyingParty.for(host: request.host, origin: request.base_url))
  def credential_param = params.require(:credential).to_unsafe_h

  def require_recent_verification
    return if Current.session.verified_recently?

    message = "ログインから 10 分を過ぎたので、パスワードかパスキーで本人を確かめてください"
    respond_to do |format|
      format.json { render json: {ok: false, code: "reverify", message:}, status: :forbidden }
      format.any { redirect_to passkeys_path, alert: message }
    end
  end
end
