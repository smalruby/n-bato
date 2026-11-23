class Current < ActiveSupport::CurrentAttributes
  attribute :session
  # 操作履歴(Audit)
  attribute :audit_operation, :audit_pending, :audit_scope, :audit_disabled, :audit_in_block
  # 操作する年度(デザインシステム「年度」)
  attribute :working_year
  delegate :user, to: :session, allow_nil: true
end
