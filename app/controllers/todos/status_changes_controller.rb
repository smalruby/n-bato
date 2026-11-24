# やることの状態を変える(作業中・待ち・済みにする・未着手に戻す)。済みも元に戻せる(操作履歴)。docs/adr/0034
class Todos::StatusChangesController < ApplicationController
  def create
    todo = Todo.find(params[:todo_id])
    status = params[:status].presence_in(Todo::STATUSES.keys) or return redirect_back(fallback_location: todos_path, alert: "状態が分かりません")

    Todo::StatusChange.change!(todo, status:, waiting_on: params[:waiting_on].to_s, note: params[:done_note].to_s, by: Current.user)
    redirect_back fallback_location: todos_path, notice: "「#{todo.title}」を#{todo.status_label}にしました(元に戻せます)"
  end

  private

  def audit_scope = "todos"
end
