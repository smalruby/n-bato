# 操作の中の、1 件の記録の変化。
class AuditChange < ApplicationRecord
  self.audited = false
  IGNORED = %w[id created_at updated_at].freeze

  belongs_to :audit_operation
  serialize :changeset, coder: JSON
  serialize :snapshot, coder: JSON
  encrypts :changeset, :snapshot

  def auditable_class = auditable_type.safe_constantize
  def record = auditable_class&.find_by(id: auditable_id)
  def model_label = auditable_class&.model_name&.human || auditable_type

  def fields = (changeset || {}).keys
  # 記録の列の値(削除なら消す前の値、ほかは変えたあとの値)。元に戻すときの、持ち主の記録を探すのに使う。
  def value(field) = snapshot ? snapshot[field] : Array((changeset || {})[field]).compact.last
  def field_label(name) = auditable_class&.human_attribute_name(name) || name

  scope :in_fiscal_year, ->(year) { where(fiscal_year: year) }

  def summary
    case event
    when "create" then "追加: #{model_label}"
    when "destroy" then "削除: #{model_label}"
    else "変更: #{model_label}の#{fields.map { field_label(it) }.uniq.first(3).join("・")}"
    end
  end
end
