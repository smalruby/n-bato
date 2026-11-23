# 科目と部門(年度ごとのデータセット)。操作している年度の科目と部門を出す。
class AccountsController < ApplicationController
  include AutosaveResponse
  undoable_screen

  EDITABLE = %i[category group_name].freeze

  def index
    @year = Current.working_year
    @tab = params[:tab] == "departments" ? "departments" : "accounts"
    @usage = Hash.new(0)
    entries = JournalEntry.active.in_fiscal_year(@year)
    entries.group(:debit_account_id).count.each { |id, n| @usage[id] += n }
    entries.group(:credit_account_id).count.each { |id, n| @usage[id] += n }
    @accounts = Account.in_year(@year).ordered.to_a
    @accounts.select! { @usage[it.id].positive? } if params[:used] == "1"
    @departments = Department.in_year(@year).ordered
  end

  def edit
    @account = Account.find(params[:id])
  end

  # 1 項目ずつ保存する。締めた年度は理由を書いてもらう。保存したら、ほかの締めていない年度に
  # 同じ値の同じ科目があれば、それも直すかを聞く(also)。
  def update
    @account = Account.find(params[:id])
    attrs = params.require(:account).permit(*EDITABLE)
    period = FiscalPeriod.for(@account.fiscal_year)
    if period&.closed? && params[:reason].to_s.strip.empty? && request.format.json?
      return render json: { ok: false, code: "reason_required", states: { period.year => { label: period.label, state: period.state, state_label: period.state_label } },
                            message: "#{period.label}は締めた年度です。直す理由を書いてください。" }, status: :conflict
    end
    if period&.closed?
      Audit.reason!(params[:reason].to_s.strip)
      FiscalPeriod.changed_after_close!(period.year)
      Audit.label!("締めた年度(#{period.year}年度)の科目を直した")
    end
    before = attrs.keys.to_h { [ it, @account.public_send(it) ] }
    saved = @account.update(attrs)
    respond_to do |format|
      format.json { autosave_response(@account, also: (saved ? also_years(before) : nil)) }
      format.html do
        if saved
          redirect_to accounts_path, notice: "#{@account} の区分を変更しました"
        else
          render :edit, status: :unprocessable_entity
        end
      end
    end
  end

  # ほかの年度にも同じ変更を効かせる(締めていない年度だけ。締めた年度はその年度に切り替えて理由を書いて直す)
  def apply_to_years
    account = Account.find(params[:id])
    field = EDITABLE.map(&:to_s).find { it == params[:field] } or return head(:unprocessable_entity)
    years = Array(params[:years]).map(&:to_i)
    targets = years.filter_map { |y| FiscalPeriod.for(y)&.closed? ? nil : account.in_year(y) }
    Audit.label!("#{account.display_name}の#{Account.human_attribute_name(field)}を #{targets.map { "#{it.fiscal_year}年度" }.join('・')}にも効かせた")
    targets.each { it.update!(field => account.public_send(field)) }
    autosave_response(account)
  end

  private

  def also_years(before)
    field, old = before.find { |k, v| @account.public_send(k) != v } || return
    others = FiscalPeriod.ordered.reject { it.closed? || it.year == @account.fiscal_year }.filter_map do |p|
      other = @account.in_year(p.year)
      other && other.public_send(field) == old ? p : nil
    end
    return nil if others.empty?

    { field:, years: others.map(&:year), labels: others.map(&:label), url: apply_to_years_account_path(@account, format: :json),
      message: "#{others.map(&:label).join('・')}の#{@account.display_name}も、同じ#{Account.human_attribute_name(field)}にしますか。" }
  end
end
