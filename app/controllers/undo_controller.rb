# 元に戻す・やり直す(上部バーの UndoBar と ⌘Z / ⌘⇧Z)。
class UndoController < ApplicationController
  skip_around_action :record_operation

  def undo = perform { Audit.undo!(Current.user, scope) }
  def redo = perform { Audit.redo!(Current.user, scope) }

  # 右ペインの操作履歴(turbo-frame で読み直す)
  def history
    @operations = AuditOperation.where(scope:).recent.includes(:user, :audit_changes).limit(40)
    render partial: "shared/history", locals: {operations: @operations, scope:}
  end

  private

  def scope = params.require(:scope)

  # 元に戻した記録のある画面・年度・行へ移り、セルを光らせる(デザインシステム UndoBar)
  def jump_to(op)
    change = op&.target&.audit_changes&.first or return {}
    record = change.record
    location = case record
    when JournalEntry then journal_entries_path(year: record.fiscal_year)
    when Account then accounts_path
    end
    field = (change.event == "update") ? Audit.display_field(change.fields.first) : nil
    {location:, highlight: {record: "#{change.auditable_type.underscore}_#{change.auditable_id}", field:}}.compact
  end

  def perform
    op = yield
    message = op ? op.label : "元に戻せる操作はありません"
    respond_to do |format|
      format.json { render json: {ok: true, message:, **Audit.bar(Current.user, scope), **jump_to(op), saved_at: I18n.l(Time.current, format: "%H:%M")} }
      format.html { redirect_back_or_to(root_path, notice: message) }
    end
  rescue Audit::Conflict => e
    respond_to do |format|
      format.json { render json: {ok: false, message: e.message}, status: :conflict }
      format.html { redirect_back_or_to(root_path, alert: e.message) }
    end
  end
end
