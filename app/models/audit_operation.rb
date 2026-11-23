# 1 回の操作。元に戻す・やり直すの単位(docs/design-system/README.md「保存と履歴の決まり」)。
#
# kind:
#   do    ふつうの操作。元に戻せる(state が active のあいだ)
#   final 元に戻せない操作(承認・提出日の記録など)。履歴には残る
#   undo  「元に戻す」をした記録。target が戻した操作
#   redo  「やり直す」をした記録。target がやり直した操作
class AuditOperation < ApplicationRecord
  KINDS = %w[do final undo redo].freeze
  self.audited = false

  belongs_to :user, optional: true
  belongs_to :target, class_name: "AuditOperation", optional: true
  has_many :audit_changes, -> { order(:id) }, dependent: :destroy

  validates :kind, inclusion: { in: KINDS }

  scope :recent, -> { order(id: :desc) }
  scope :in_scope, ->(user, scope) { where(user:, scope:) }
  scope :undoable, -> { where(kind: "do", state: "active") }
  scope :redoable_ops, -> { where(kind: "do", state: "undone", redoable: true) }

  def undoable? = kind == "do" && state == "active"
  def final? = kind == "final"

  # 変更の中身から、履歴に出す短い説明を作る(label が無いとき)。
  def describe
    return label if label.present?

    c = audit_changes.first
    return "(変更なし)" unless c

    text = c.summary
    audit_changes.size > 1 ? "#{text} ほか #{audit_changes.size - 1} 件" : text
  end
end
