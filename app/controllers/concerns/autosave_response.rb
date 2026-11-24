# 自動保存(autosave_controller.js)への返事。
module AutosaveResponse
  private

  def autosave_response(record, value: nil, **extra)
    if record.errors.empty?
      Audit.finish(Current.audit_operation)
      render json: {ok: true, saved_at: I18n.l(Time.current, format: "%H:%M"), value:, **extra,
                    **Audit.bar(Current.user, Current.audit_scope)}.compact
    else
      render json: {ok: false, message: "保存できませんでした(#{record.errors.full_messages.join("、")})", errors: record.errors.to_hash},
        status: :unprocessable_content
    end
  end
end
