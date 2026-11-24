class CreateAuditTables < ActiveRecord::Migration[8.1]
  def change
    # 1 回の操作(セルの変更、行の追加、承認など)。元に戻す・やり直すの単位。
    create_table :audit_operations do |t|
      t.references :user, foreign_key: true
      t.string :scope            # 画面(元に戻すはこの画面の中の自分の操作だけ)
      t.string :kind, null: false, default: "do" # do / undo / redo / final(元に戻せない)
      t.string :state, null: false, default: "active" # active / undone
      t.boolean :redoable, null: false, default: false
      t.references :target, foreign_key: {to_table: :audit_operations} # undo・redo が対象にした操作
      t.string :label
      t.timestamps
    end
    add_index :audit_operations, [:user_id, :scope, :kind, :state]

    # 操作の中の 1 件の記録の変化。暗号化した項目(住所など)もあるので中身は暗号化する。
    create_table :audit_changes do |t|
      t.references :audit_operation, null: false, foreign_key: true
      t.string :auditable_type, null: false
      t.integer :auditable_id, null: false
      t.string :event, null: false # create / update / destroy
      t.text :changeset            # {項目: [変更前, 変更後]}
      t.text :snapshot             # 削除したときの全項目(元に戻すため)
      t.timestamps
    end
    add_index :audit_changes, [:auditable_type, :auditable_id]
  end
end
