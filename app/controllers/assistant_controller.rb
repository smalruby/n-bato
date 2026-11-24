# 右ペイン「AI に聞く」(デザインシステム AskAI)。
class AssistantController < ApplicationController
  include HelpHelper

  def create
    return render(json: {answer: "AI の鍵(ANTHROPIC_API_KEY)が設定されていないので、いまは答えられません。"}) unless Bookkeeper::Client.configured?

    question = params[:q].to_s.strip
    return render(json: {answer: "聞きたいことを書いてください。"}) if question.empty?

    blob = params[:image].presence && ActiveStorage::Blob.create_and_upload!(io: params[:image], filename: params[:image].original_filename, content_type: params[:image].content_type)
    screen = params[:screen].to_s[/\A[a-z_]{1,40}\z/] || "default"
    year = Current.working_year
    result = Assistant::Responder.new(screen:, year:, help: help_content(screen)).call(question, image: blob)
    action, problem = Current.user.auditor? ? [nil, nil] : Assistant::Action.prepare(result.action, year:, image_blob: blob)
    render json: {answer: [result.answer, problem].compact.join("\n"), action:}
  rescue Bookkeeper::Client::Error => e
    render json: {answer: "AI に聞けませんでした(#{e.message})。"}
  end

  def perform
    return render(json: {ok: false, message: "監査の役割では、記録を変えられません"}, status: :forbidden) if Current.user.auditor?

    message, location = Assistant::Action.perform(params.require(:token), reason: params[:reason])
    render json: {ok: true, message:, location:}
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    render json: {ok: false, message: "操作の案が正しくありません。もう一度聞いてください"}, status: :unprocessable_content
  rescue ArgumentError, ActiveRecord::RecordInvalid, Bookkeeper::Client::Error => e
    # 証憑を保存できない(受け付けない形のファイルなど)。AI のエラーは ProposalGenerator が証憑に残すので、ここまでは来ない
    render json: {ok: false, message: e.message}, status: :unprocessable_content
  end
end
