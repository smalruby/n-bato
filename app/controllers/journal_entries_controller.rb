class JournalEntriesController < ApplicationController
  include AutosaveResponse

  undoable_screen
  before_action :set_entry, only: %i[show edit update destroy]
  before_action :require_editable, only: %i[edit update destroy]

  def index
    @counts = JournalEntry.active.group(:fiscal_year).count
    @year = Current.working_year
    @accounts = Account.in_year(@year).ordered.where.not(category: "special")
    @departments = Department.in_year(@year).ordered
    @filter = journal_filter
    entries = JournalEntry.in_fiscal_year(@year).chronological
      .includes(:debit_account, :credit_account, :debit_department, :credit_department, :siwake_import, {journal_proposal: :voucher}, cancellation: :canceller)
    # 取り消した仕訳は、絞り込みの「取り消した仕訳も出す」のときだけ出す(docs/adr/0026)
    entries = entries.active unless @filter[:cancelled]
    if (id = @filter[:account_id])
      entries = entries.where("debit_account_id = :id OR credit_account_id = :id", id:)
      @balance_account = Account.in_year(@year).find_by(id:)
      @balance = Ledger::Book.new.account_ledger(@balance_account, @year)[:closing] if @balance_account
    end
    entries = entries.where("debit_department_id = :id OR credit_department_id = :id", id: @filter[:department_id]) if @filter[:department_id]
    entries = entries.where("summary LIKE :q OR sub_summary LIKE :q", q: "%#{JournalEntry.sanitize_sql_like(@filter[:q])}%") if @filter[:q]
    @entries = entries
    @new_row_date = new_row_date
    @filter_label = [@balance_account&.display_name, Department.in_year(@year).find_by(id: @filter[:department_id])&.display_name, @filter[:q] && "「#{@filter[:q]}」", @filter[:cancelled] && "取り消した仕訳も出す"].compact.join("・")
  end

  def show
  end

  def new
    @entry = JournalEntry.new(entry_date: Date.current)
  end

  def create
    @entry = JournalEntry.new(entry_params)
    return if request.format.json? && year_guard(from: sheet_year, to: @entry.entry_date && FiscalYear.for(@entry.entry_date).year)

    saved = @entry.save
    session[:new_row_date] = @entry.entry_date.iso8601 if saved
    respond_to do |format|
      # 表のいちばん下の行から(デザインシステム Sheet の「新しい行」)
      format.json { autosave_response(@entry, record: helpers.dom_id(@entry), location: journal_entries_path(year: @entry.fiscal_year)) }
      format.html do
        if saved
          redirect_to journal_entries_path(year: @entry.fiscal_year), notice: "仕訳を登録しました"
        else
          render :new, status: :unprocessable_content
        end
      end
    end
  end

  def edit
  end

  def update
    from = @entry.fiscal_year
    @entry.assign_attributes(entry_params)
    to = @entry.entry_date ? FiscalYear.for(@entry.entry_date).year : from
    return if request.format.json? && year_guard(from:, to:)

    saved = @entry.save
    respond_to do |format|
      format.json do
        moved = @entry.saved_change_to_fiscal_year?
        autosave_response(@entry, value: autosave_value,
                          **(moved ? {record: helpers.dom_id(@entry), location: journal_entries_path(year: @entry.fiscal_year)} : {}))
      end
      format.html do
        if saved
          redirect_to journal_entries_path(year: @entry.fiscal_year), notice: "仕訳を更新しました"
        else
          render :edit, status: :unprocessable_content
        end
      end
    end
  end

  # AI の提案を承認してできた仕訳は消さない(訂正は訂正の仕訳。docs/adr/0007)。止めるのは require_editable
  def destroy
    if FiscalPeriod.for(@entry.fiscal_year)&.closed?
      reason = params[:reason].to_s.strip
      return redirect_to(journal_entries_path(year: @entry.fiscal_year), alert: "#{@entry.fiscal_year}年度は締めた年度です。消す理由を書いてください") if reason.empty?

      Audit.reason!(reason)
      FiscalPeriod.changed_after_close!(@entry.fiscal_year)
      Audit.label!("締めた年度(#{@entry.fiscal_year}年度)の仕訳を消した")
    end
    @entry.destroy!
    redirect_to journal_entries_path(year: @entry.fiscal_year), notice: "仕訳を削除しました(元に戻せます)"
  end

  # 年度の仕訳を会計王の SIWAKE 形式で書き出す
  def export
    year = Integer(params[:fiscal_year_year])
    scope = JournalEntry.active.in_fiscal_year(year).chronological.includes(:debit_account, :credit_account, :debit_department, :credit_department)
    scope = scope.where(siwake_import_id: nil) if params[:only] == "new"
    file = Kaikeiou::SiwakeFile.new(rows: scope.map(&:to_siwake_row))
    send_data file.to_bytes, filename: "siwake_#{year}#{"_new" if params[:only] == "new"}.txt", type: "text/plain; charset=Shift_JIS"
  end

  private

  def set_entry = @entry = JournalEntry.find(params[:id])

  # 新しい行の日付の初期値。今日がこの年度の外なら、この年度のいちばん後の仕訳の日付にする
  # (カレンダーが今日の月で開くと、別の年度の日付を入れやすいため)。今日が年度の中なら空のまま。
  # 直前にこの年度へ足した仕訳があれば、その日付を使う。
  def new_row_date
    fy = FiscalYear.new(@year)
    return if fy.range.cover?(Date.current)

    last = begin
      Date.parse(session[:new_row_date])
    rescue
      nil
    end   # 直前に足した仕訳の日付
    return last if last && fy.range.cover?(last)

    JournalEntry.in_fiscal_year(@year).maximum(:entry_date) || fy.starts_on
  end

  # 金額は桁区切りを付けて返す(入力欄の表示をそろえる)
  def autosave_value
    params.dig(:journal_entry, :amount) ? @entry.amount.to_s : nil
  end

  def require_editable
    return unless (blocked = @entry.edit_blocked_reason)

    message = blocked.message
    respond_to do |format|
      format.json { render json: {ok: false, message:}, status: :forbidden }
      format.html { redirect_to @entry, alert: message }
    end
  end

  # 表の年度(画面が送る)。送られなければ操作している年度。
  def sheet_year = params[:sheet_year].presence&.to_i || Current.working_year

  # デザインシステム「年度」: 年度の外の日付は保存せずに知らせ、「移す」を押したら移す。
  # 締めた年度にかかる変更は、理由を書いてもらう。止めたときは true を返す(JSON を返し済み)。
  def year_guard(from:, to:)
    years = [from, to].compact.uniq
    missing = years.reject { FiscalPeriod.for(it) }
    if missing.any?
      render json: {ok: false, code: "no_year", message: "#{missing.first}年度はまだ始めていません。日付を直してください"}, status: :conflict
      return true
    end
    if to && from && to != from && params[:move].blank?
      render json: {ok: false, code: "outside_year", from:, to:, states: year_states(years), reason_required: years.any? { FiscalPeriod.for(it).closed? },
                    message: "#{@entry.entry_date.strftime("%Y/%m/%d")} は #{FiscalPeriod.for(to).label}の日付です。この表は #{FiscalPeriod.for(from).label}なので、まだ保存していません。"},
        status: :conflict
      return true
    end
    closed = years.select { FiscalPeriod.for(it).closed? }
    if closed.any? && params[:reason].to_s.strip.empty?
      render json: {ok: false, code: "reason_required", states: year_states(years),
                    message: "#{closed.map { FiscalPeriod.for(it).label }.join("・")}は締めた年度です。直すと、提出した書類と合わなくなることがあります。直す理由を書いてください。"},
        status: :conflict
      return true
    end
    if closed.any?
      Audit.reason!(params[:reason].to_s.strip)
      FiscalPeriod.changed_after_close!(closed)
      Audit.label!("締めた年度(#{closed.map { "#{it}年度" }.join("・")})の仕訳を直した")
    end
    false
  end

  def year_states(years) = years.to_h { |y|
    p = FiscalPeriod.for(y)
    [y, {label: p.label, state: p.state, state_label: p.state_label}]
  }

  # 絞り込み(デザインシステム FilterBar)。画面を離れても保つ。
  def journal_filter
    session.delete(:journal_filter) if params[:clear]
    if params.key?(:account_id) || params.key?(:department_id) || params.key?(:q) || params.key?(:cancelled)
      session[:journal_filter] = {"account_id" => params[:account_id].presence&.to_i, "department_id" => params[:department_id].presence&.to_i,
                                  "q" => params[:q].to_s.strip.presence, "cancelled" => params[:cancelled] == "1" || nil}.compact
    end
    filter = (session[:journal_filter] || {}).symbolize_keys
    # 絞り込みの科目・部門は年度ごとのデータセットなので、操作している年度の同じコードに付け替える
    {account_id: Account, department_id: Department}.each do |key, klass|
      next unless (id = filter[key])
      record = klass.find_by(id:)
      filter[key] = record&.in_year(Current.working_year)&.id
    end
    filter.compact
  end

  def entry_params
    params.require(:journal_entry).permit(:entry_date, :amount, :debit_account_id, :debit_department_id,
      :credit_account_id, :credit_department_id, :summary, :sub_summary, :memo)
  end
end
