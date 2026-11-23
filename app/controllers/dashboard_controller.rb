class DashboardController < ApplicationController
  def show
    return redirect_to(setup_path) if Organization.none? # 最初の起動はウィザードへ(見直し第17回)

    @organization = Organization.current
    todo_list = TodoList.new(helpers:)
    @near = todo_list.near
    @todo_summary = todo_list.summary
    @book = Ledger::Book.new
    @statements = @book.statements.last(5).reverse
    @imports = SiwakeImport.order(created_at: :desc).limit(5)
  end
end
