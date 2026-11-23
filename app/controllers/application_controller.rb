class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :set_audit_scope
  before_action :set_working_year
  before_action :read_only_for_auditor
  after_action :remember_list_url
  around_action :record_operation, unless: -> { request.get? || request.head? }

  # 元に戻す・やり直すを出す画面は、コントローラで undoable_screen を宣言する。
  class_attribute :undoable_screen_flag, default: false
  def self.undoable_screen = self.undoable_screen_flag = true

  private

  # 「開く」で来たやることの対象が、いま操作している締めた年度なら、理由の欄に最初から入れておく文(デザインシステム「やること」)
  helper_method :todo_reason_hint
  def todo_reason_hint
    return @todo_reason_hint if defined?(@todo_reason_hint)

    todo = session[:todo_context] && Todo.find_by(id: session[:todo_context])
    @todo_reason_hint = todo && todo.fiscal_year == Current.working_year && FiscalPeriod.for(todo.fiscal_year)&.closed? ? todo.reason_hint : nil
  end


  # まだ年度で分けていない画面(デザインシステム「年度」)。その旨の帯を出す。分け終えたら外す。
  class_attribute :year_split_pending_flag, default: false
  def self.year_split_pending = self.year_split_pending_flag = true

  # 監査の役割は閲覧だけ(デザインシステム「役割」)。説明の畳み・AI に聞く・役割の切り替え・ログアウト・自分のパスキーは許す。
  READ_ONLY_ALLOWED = %w[sessions passkey_sessions passkeys ui_prefs working_years assistant roles pickers].freeze
  def read_only_for_auditor
    return if request.get? || request.head? || !Current.user&.auditor? || controller_name.in?(READ_ONLY_ALLOWED)

    message = "監査の役割では、記録を変えられません"
    respond_to do |format|
      format.json { render json: { ok: false, message: }, status: :forbidden }
      format.any { redirect_back fallback_location: root_path, alert: message }
    end
  end

  # 操作する年度。URL に年度(year / fiscal_year_year)があれば、その年度に切り替えて覚える。
  def set_working_year
    return unless Current.user

    FiscalPeriod.ensure! if FiscalPeriod.none?
    years = FiscalPeriod.years
    requested = (params[:year] || params[:fiscal_year_year]).to_s[/\A\d{4}\z/]&.to_i
    if requested && years.include?(requested) && requested != Current.user.working_year
      Current.user.update_column(:working_year, requested)
    end
    year = Current.user.working_year
    year = FiscalYear.current.year unless years.include?(year)
    Current.working_year = year
    @working_period = FiscalPeriod.for(year)
  end

  # 元に戻すの範囲(画面)。ふつうはコントローラの名前。
  def audit_scope = controller_name

  def set_audit_scope
    Current.audit_scope = params[:undo_scope].presence || audit_scope
    @undo_scope = Current.audit_scope if undoable_screen_flag
  end

  # 1 回のリクエストの変更を 1 つの操作にまとめる(操作履歴)。
  def record_operation(&)
    Audit.operation(user: Current.user, scope: Current.audit_scope) { ApplicationRecord.transaction(&) }
  end

  # 一覧で最後に開いた絞り込み・並べ替えを覚えておき、詳しい画面のパンくずから同じ状態で戻れるようにする(見直し第21回)
  def remember_list_url
    return unless request.get? && action_name == "index" && request.format.html? && response.successful?

    urls = (session[:list_urls] ||= {})
    request.query_string.present? ? urls[request.path] = request.fullpath : urls.delete(request.path)
    session[:list_urls] = urls.to_a.last(20).to_h
  end
end
