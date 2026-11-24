# すべての記録の作成・変更・削除を、いまの操作(Current.audit_operation)の変化として残す。
# 画面からの操作は ApplicationController が操作の始まりと終わりを決める。rake などでは 1 件ごとに操作を作る。
module Audited
  extend ActiveSupport::Concern

  included do
    class_attribute :audited, default: true
    after_create { audit_record("create") }
    after_update { audit_record("update") }
    after_destroy { audit_record("destroy") }
  end

  # 変更の記録で、どの年度の変更として並べるか(デザインシステム「年度」の変更の記録)。
  # 年度の列があればそれ、無ければ日付の列から決める。年度に属さない記録は nil。
  AUDIT_DATE_COLUMNS = %w[entry_date issued_on proposed_on cause_on checked_on starts_on consented_on].freeze

  def audit_fiscal_year
    return self[:fiscal_year] if has_attribute?(:fiscal_year) && self[:fiscal_year]
    return self[:period] if is_a?(ProcedureRun)
    return procedure_run&.period if is_a?(ProcedureStep)

    col = AUDIT_DATE_COLUMNS.find { has_attribute?(it) && self[it] }
    col ? FiscalYear.for(self[col]).year : nil
  end

  private

  def audit_record(event)
    return unless self.class.audited && !Audit.disabled?

    changeset = case event
    when "create" then attributes.except(*AuditChange::IGNORED).compact.transform_values { [nil, it] }
    when "update" then saved_changes.except(*AuditChange::IGNORED)
    else attributes.except(*AuditChange::IGNORED).compact.transform_values { [it, nil] }
    end
    return if event == "update" && changeset.empty?

    Audit.current_operation.audit_changes.create!(
      auditable_type: self.class.name, auditable_id: id, event:, fiscal_year: audit_fiscal_year,
      changeset: changeset.transform_values { |v| v.map { Audit.dump(it) } },
      snapshot: (event == "destroy") ? attributes.transform_values { Audit.dump(it) } : nil
    )
  end
end
