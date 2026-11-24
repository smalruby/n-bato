# 操作履歴と、元に戻す・やり直す。
module Audit
  class Conflict < StandardError; end

  module_function

  def dump(value)
    case value
    when Date, Time, ActiveSupport::TimeWithZone, DateTime then value.iso8601
    when BigDecimal then value.to_s
    else value
    end
  end

  def disabled? = Current.audit_disabled

  # ブロックの中の変更を 1 つの操作にまとめる。kind: "final" は元に戻せない操作。
  # 操作は最初の変更が起きたときに作る(変更の無いリクエストでは作らない)。
  def operation(user: Current.user, scope: Current.audit_scope, kind: "do", label: nil)
    return yield if Current.audit_in_block # 入れ子は外側の操作にまとめる

    begin
      Current.audit_in_block = true
      Current.audit_pending = { user:, scope:, kind:, label:, reason: nil }
      result = yield
      finish(Current.audit_operation)
      result
    ensure
      Current.audit_operation = nil
      Current.audit_pending = nil
      Current.audit_in_block = false
    end
  end

  # いまの操作を「元に戻せない操作」にする(承認・提出日の記録・決議の反映・登記の記録)。
  def final!(label = nil)
    if Current.audit_operation
      Current.audit_operation.update!(kind: "final", label: label || Current.audit_operation.label)
    elsif Current.audit_pending
      Current.audit_pending[:kind] = "final"
      Current.audit_pending[:label] = label if label
    end
  end

  def label!(label)
    Current.audit_operation&.update!(label:)
    Current.audit_pending[:label] = label if Current.audit_pending
  end

  # 締めた年度を直した理由を、いまの操作に残す(変更の記録に出す)。
  def reason!(reason)
    Current.audit_operation&.update!(reason:)
    Current.audit_pending[:reason] = reason if Current.audit_pending
  end

  # 操作の外(rake など)では、変更 1 件ごとに操作を作る。
  def current_operation
    return Current.audit_operation if Current.audit_operation

    attrs = Current.audit_pending || { user: Current.user, scope: Current.audit_scope, kind: "do", label: nil, reason: nil }
    op = AuditOperation.create!(**attrs)
    Current.audit_operation = op if Current.audit_in_block
    op
  end

  def finish(op)
    return unless op
    # 新しい操作をしたら、それまでに元に戻した操作はやり直せなくする(ふつうのアプリと同じ)
    AuditOperation.in_scope(op.user, op.scope).redoable_ops.update_all(redoable: false) if op.kind == "do"
  end

  def without
    before = Current.audit_disabled
    Current.audit_disabled = true
    yield
  ensure
    Current.audit_disabled = before
  end

  # UndoBar に出すもの(件数と、何が戻るか)。保存・元に戻すの JSON にも入れる。
  def bar(user, scope)
    peek = peek(user, scope)
    { **counts(user, scope), undo_peek: peek[:undo], redo_peek: peek[:redo] }
  end

  # UndoBar に出す「何が戻るか」。{ undo: {item:, detail:, record:, field:}, redo: … }
  def peek(user, scope)
    { undo: preview(undo_target(user, scope), :undo), redo: preview(redo_target(user, scope), :redo) }
  end

  def preview(op, direction)
    return nil unless op

    change = op.audit_changes.order(:id).first
    return { item: op.label.to_s.truncate(20) } unless change

    if change.event == "update" && change.fields.any?
      field = change.fields.first
      before, after = change.changeset[field]
      from, to = direction == :undo ? [ after, before ] : [ before, after ]
      fmt = ->(v) { ApplicationController.helpers.history_value(change, field, v) }
      label = display_field_label(change, field)
      { item: label, detail: "#{label} #{fmt.(from)} → #{fmt.(to)}", record: "#{change.auditable_type.underscore}_#{change.auditable_id}", field: display_field(field) }
    else
      { item: change.summary.sub(/\A(追加|削除): /, "\\1した"), detail: change.summary, record: "#{change.auditable_type.underscore}_#{change.auditable_id}" }
    end
  end

  # 借方・貸方の金額は画面では「金額」1 つ
  def display_field(field) = field.to_s.sub(/\A(debit|credit)_amount\z/, "amount")
  def display_field_label(change, field) = display_field(field) == "amount" && field.to_s != "amount" ? "金額" : change.field_label(field)

  def undo_target(user, scope) = AuditOperation.in_scope(user, scope).undoable.order(:id).last
  def redo_target(user, scope) = AuditOperation.in_scope(user, scope).redoable_ops.order(updated_at: :desc, id: :desc).first

  def counts(user, scope)
    base = AuditOperation.in_scope(user, scope)
    { undo: base.undoable.count, redo: base.redoable_ops.count }
  end

  # いちばん新しい操作を元に戻す。戻した記録を新しい操作として残す。
  def undo!(user, scope)
    target = undo_target(user, scope) or return nil
    run(user, scope, "undo", target, "元に戻した: #{target.describe}") do
      target.audit_changes.reverse_each { revert(it) }
      target.update!(state: "undone", redoable: true)
    end
  end

  def redo!(user, scope)
    target = redo_target(user, scope) or return nil
    run(user, scope, "redo", target, "やり直した: #{target.describe}") do
      target.audit_changes.each { reapply(it) }
      target.update!(state: "active", redoable: false)
    end
  end

  def run(user, scope, kind, target, label)
    ApplicationRecord.transaction do
      Current.audit_in_block = true
      op = AuditOperation.create!(user:, scope:, kind:, target:, label:)
      Current.audit_operation = op
      yield
      op
    ensure
      Current.audit_operation = nil
      Current.audit_in_block = false
    end
  end

  # 元に戻す・やり直すで、記録の形が合わないとき(表の形が変わる前の操作など)。500 にせず Conflict にする。
  # StatementInvalid は NOT NULL・外部キー・一意の制約に反したとき(docs/adr/0034)。
  REVERT_ERRORS = [ ActiveRecord::RecordNotDestroyed, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid ].freeze

  def revert(change)
    klass = change.auditable_class
    case change.event
    when "create"
      record = klass.find_by(id: change.auditable_id) or return
      check_unchanged!(record, change.changeset.transform_values(&:last))
      record.destroy!
    when "update"
      record = klass.find(change.auditable_id)
      check_unchanged!(record, change.changeset.transform_values(&:last))
      write(record, change.changeset.transform_values(&:first))
    when "destroy"
      write(klass.new, change.snapshot)
    end
  rescue *REVERT_ERRORS => e
    raise Conflict, "#{change.model_label}を元に戻せませんでした(#{e.message})"
  end

  def reapply(change)
    klass = change.auditable_class
    case change.event
    when "create"
      write(klass.new(id: change.auditable_id), change.changeset.transform_values(&:last).merge("id" => change.auditable_id))
    when "update"
      record = klass.find(change.auditable_id)
      check_unchanged!(record, change.changeset.transform_values(&:first))
      write(record, change.changeset.transform_values(&:last))
    when "destroy"
      klass.find_by(id: change.auditable_id)&.destroy!
    end
  rescue *REVERT_ERRORS => e
    raise Conflict, "#{change.model_label}をやり直せませんでした(#{e.message})"
  end

  # 戻す前に、そのあと別の操作で変わっていないか確かめる。
  def check_unchanged!(record, expected)
    expected.each do |field, value|
      next unless record.has_attribute?(field)
      next if dump(record.read_attribute(field)).to_s == value.to_s

      raise Conflict, "#{record.class.model_name.human}の#{record.class.human_attribute_name(field)}が、そのあと別の操作で変わっています"
    end
  end

  def write(record, values)
    values.each { |field, value| record.write_attribute(field, value) if record.has_attribute?(field) }
    record.save!(validate: false)
  end
end
