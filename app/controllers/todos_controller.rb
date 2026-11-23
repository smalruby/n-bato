# やることの一覧(デザインシステム「やること」)。年度をまたいで 1 つの一覧にする(操作している年度では絞らない)。
class TodosController < ApplicationController
  undoable_screen
  before_action :set_todo, only: %i[update open]

  def index
    @source = params[:source].presence_in(TodoList::SOURCES.keys)
    @year = params[:fy].to_s[/\A\d{4}\z/]&.to_i
    @include_done = params[:done] == "1"
    @due = params[:due].presence_in(TodoList::DUES.keys)
    @who = params[:who].presence_in(TodoList::WHOS.keys)
    list = TodoList.new(helpers:, source: @source, year: @year, include_done: @include_done, due: @due, who: @who)
    @groups = list.groups
    @summary = list.summary
  end

  # 状態を変える(作業中・待ち・済みにする・未着手に戻す)。済みは元に戻せる(操作履歴)。
  def update
    st = params[:status].presence_in(Todo::STATUSES.keys) or return redirect_back(fallback_location: todos_path, alert: "状態が分かりません")
    attrs = { status: st }
    attrs[:waiting_on] = st == "wait" ? params[:waiting_on].to_s.strip : ""
    if st == "done"
      attrs.merge!(done_at: Time.current, done_by: "user", done_note: params[:done_note].to_s.strip)
    else
      attrs.merge!(done_at: nil, done_by: "", done_note: "")
    end
    @todo.update!(attrs)
    Audit.label!("やること「#{@todo.title}」を#{@todo.status_label}にした")
    redirect_back fallback_location: todos_path, notice: "「#{@todo.title}」を#{@todo.status_label}にしました(元に戻せます)"
  end

  # 開く: その年度に切り替えてから、解決する画面へ移る。締めた年度の理由の欄に入れておく文を覚える。
  def open
    session[:todo_context] = @todo.id
    path = @todo.target_path(helpers)
    return redirect_to(incoming_request_path(@todo.incoming_request, anchor: "todo-#{@todo.id}")) if path.nil? && @todo.incoming_request

    path ||= todos_path
    path += (path.include?("?") ? "&" : "?") + "year=#{@todo.fiscal_year}" if @todo.fiscal_year && FiscalPeriod.years.include?(@todo.fiscal_year)
    redirect_to path
  end

  private

  def set_todo = @todo = Todo.find(params[:id])
end
