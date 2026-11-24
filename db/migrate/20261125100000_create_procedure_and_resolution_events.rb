# 手続き・決議・提出を、イミュータブルデータモデルに移す(docs/adr/0002〜0008・0038)。
#
# - 手続きの手順(ProcedureStep・長いイベント)の「済みにした・対象外にした・済みを取り消した」を
#   ProcedureStep::StatusChange(イベント。日時は changed_at)に分ける。
#   procedure_steps の status・completed_on は「いまの状態」として残し、入口だけが書き換える(照合は model:verify)。
# - 事業報告(AnnualReport・長いイベント)の承認・提出・公告・出し直しが要る・出し直した の日付を、
#   AnnualReport::Milestone(イベント。日時は recorded_at、記録した日付は dated_on)に分ける。
#   annual_reports の approved_on・submitted_on・bs_published_on・resubmit_needed_on・resubmitted_on は「いまの状態」として残す。
# - 決議の議案の「記録に反映した」(resolution_items.applied_on)を ResolutionItem::Application に移す(列は消す)。
# - 同意(Consent)をイベントにする(日付は consented_on。created_at・updated_at は消す)。
#   「取り消す」は消さずに Consent::Cancellation を足す。取り消したあとに同じ人の同意を記録し直せるよう、
#   (決議・人)の一意の索引は外す(取り消していない同意が 1 人 1 つであることは、検証と model:verify で確かめる)。
# - これまでの操作のうち、これらの記録に触れたもの(作成・変更・削除)は、元に戻す・やり直すとイベントと食い違うか
#   失敗するので、元に戻せない操作にする(やること・依頼を移したときと同じ。docs/adr/0034)。
class CreateProcedureAndResolutionEvents < ActiveRecord::Migration[8.1]
  MODELS = %w[ProcedureRun ProcedureStep AnnualReport Resolution ResolutionItem Consent].freeze

  def up
    create_table :procedure_step_status_changes do |t|
      t.references :procedure_step, null: false, foreign_key: true
      t.string :status, null: false
      t.date :completed_on
      t.text :note, default: "", null: false
      t.references :changed_by, foreign_key: { to_table: :users }
      t.datetime :changed_at, null: false
    end
    create_table :annual_report_milestones do |t|
      t.references :annual_report, null: false, foreign_key: true
      t.string :kind, null: false
      t.date :dated_on
      t.boolean :automatic, default: false, null: false
      t.references :recorded_by, foreign_key: { to_table: :users }
      t.datetime :recorded_at, null: false
    end
    create_table :resolution_item_applications do |t|
      t.references :resolution_item, null: false, foreign_key: true, index: { unique: true }
      t.references :applied_by, foreign_key: { to_table: :users }
      t.date :applied_on, null: false
    end
    create_table :consent_cancellations do |t|
      t.references :consent, null: false, foreign_key: true, index: { unique: true }
      t.references :cancelled_by, foreign_key: { to_table: :users }
      t.datetime :cancelled_at, null: false
    end

    # 手順: おかしな行を、いまの状態の形にそろえる。
    # - 決まった値(open・done・skipped)でない状態は open。
    # - 済み・対象外で日付の無いものは、更新した日(日本時間。updated_at は UTC。夏時間は無い)。
    # - open で日付のあるもの(済みを取り消したのに日付が残った)は、日付を消す。
    execute "UPDATE procedure_steps SET status = 'open' WHERE status NOT IN ('open', 'done', 'skipped')"
    execute "UPDATE procedure_steps SET completed_on = date(updated_at, '+9 hours') WHERE status IN ('done', 'skipped') AND completed_on IS NULL"
    execute "UPDATE procedure_steps SET completed_on = NULL WHERE status = 'open'"
    execute <<~SQL
      INSERT INTO procedure_step_status_changes (procedure_step_id, status, completed_on, note, changed_at)
      SELECT id, status, completed_on, CASE WHEN status = 'skipped' THEN COALESCE(note, '') ELSE '' END, updated_at
      FROM procedure_steps WHERE status <> 'open'
    SQL

    # 事業報告: 日付の入っている列ごとに、節目のイベントを 1 つ。出し直しが要る は決まりで付けたもの(automatic)
    { "approved" => "approved_on", "submitted" => "submitted_on", "bs_published" => "bs_published_on",
      "resubmit_needed" => "resubmit_needed_on", "resubmitted" => "resubmitted_on" }.each do |kind, column|
      execute <<~SQL
        INSERT INTO annual_report_milestones (annual_report_id, kind, dated_on, automatic, recorded_at)
        SELECT id, '#{kind}', #{column}, #{kind == 'resubmit_needed' ? 1 : 0}, updated_at
        FROM annual_reports WHERE #{column} IS NOT NULL
      SQL
    end

    # 議案: 反映した日を、反映のイベントへ
    execute <<~SQL
      INSERT INTO resolution_item_applications (resolution_item_id, applied_on)
      SELECT id, applied_on FROM resolution_items WHERE applied_on IS NOT NULL
    SQL
    remove_column :resolution_items, :applied_on

    remove_index :consents, %i[resolution_id person_id]
    add_index :consents, %i[resolution_id person_id]
    remove_column :consents, :created_at
    remove_column :consents, :updated_at

    # 変化の中身(changeset)は暗号化してあり SQL では読めないので、記録の種類だけで決める。
    execute <<~SQL
      UPDATE audit_operations SET kind = 'final'
      WHERE kind = 'do' AND id IN (
        SELECT audit_operation_id FROM audit_changes
        WHERE auditable_type IN (#{MODELS.map { "'#{it}'" }.join(', ')})
      )
    SQL
  end

  # 戻さないもの:
  # - up で元に戻せない操作(final)にした、これまでの操作。
  # - up でそろえた手順の状態・日付(おかしな行)。
  # - 取り消した同意(Consent::Cancellation のある同意)は、移す前の形では「消した」ものなので、行ごと消す。
  # - up のあとにできた操作の変化のうち、新しいイベントの表のもの。表を消すので、その操作を元に戻す・やり直すと Conflict になる。
  # 止めるもの:
  # - 取り消していない同意が同じ人に 2 つ以上あるとき(元に戻すの食い違いなど)。移す前の一意の索引を戻せないので、
  #   どれを残すかを人が決めて(取り消すか消すかして)から戻す。勝手には消さない。
  def down
    duplicated = select_rows(<<~SQL)
      SELECT resolution_id, person_id FROM consents WHERE id NOT IN (SELECT consent_id FROM consent_cancellations)
      GROUP BY resolution_id, person_id HAVING COUNT(*) > 1 ORDER BY resolution_id, person_id
    SQL
    if duplicated.any?
      raise ActiveRecord::IrreversibleMigration,
            "取り消していない同意が同じ人に 2 つ以上あるので戻せません(#{duplicated.map { |r, p| "決議 ##{r}・人 ##{p}" }.join('、')})。" \
            "どれを残すかを決めて、ほかを取り消してから戻してください"
    end

    cancelled = select_values("SELECT consent_id FROM consent_cancellations")
    drop_table :consent_cancellations
    execute "DELETE FROM consents WHERE id IN (#{cancelled.map(&:to_i).join(', ')})" if cancelled.any?
    add_column :consents, :created_at, :datetime
    add_column :consents, :updated_at, :datetime
    execute "UPDATE consents SET created_at = consented_on, updated_at = consented_on"
    change_column_null :consents, :created_at, false
    change_column_null :consents, :updated_at, false
    remove_index :consents, %i[resolution_id person_id]
    add_index :consents, %i[resolution_id person_id], unique: true

    add_column :resolution_items, :applied_on, :date
    execute <<~SQL
      UPDATE resolution_items SET applied_on = (SELECT applied_on FROM resolution_item_applications a WHERE a.resolution_item_id = resolution_items.id)
    SQL
    # procedure_steps と annual_reports の「いまの状態」の列は、イベントを分けたあとも同じ値を持っているので戻さなくてよい
    drop_table :resolution_item_applications
    drop_table :annual_report_milestones
    drop_table :procedure_step_status_changes
  end
end
