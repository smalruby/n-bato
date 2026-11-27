# 会員資格の会費の納入と、役員の任期の退任を、イベントに分ける(#17、docs/adr/0030)。
# memberships.fee_amount・fee_paid_on と officer_terms.left_on は列の書き換えで出来事を表していたので、
# 納めた日・退任した日を 1 つだけ持つイベント(Membership::FeePayment・OfficerTerm::Resignation)へ移し、古い列を消す。
# いまの行から SQL でイベントを作る(データを捨てない)。down は古い列を作り直してデータを戻す。
class CreateFeePaymentAndResignationEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :membership_fee_payments do |t|
      t.references :membership, null: false, foreign_key: true, index: {unique: true}
      t.references :recorder, foreign_key: {to_table: :users}
      t.integer :amount, null: false
      t.date :paid_on, null: false
    end
    create_table :officer_term_resignations do |t|
      t.references :officer_term, null: false, foreign_key: true, index: {unique: true}
      t.references :recorder, foreign_key: {to_table: :users}
      t.text :reason, null: false, default: ""
      t.date :left_on, null: false
    end
    # 納めた日だけあって金額の無い行は 0 円として残す(金額が分からなかった記録。消さない)
    execute <<~SQL
      INSERT INTO membership_fee_payments (membership_id, amount, paid_on)
      SELECT id, COALESCE(fee_amount, 0), fee_paid_on FROM memberships WHERE fee_paid_on IS NOT NULL
    SQL
    execute <<~SQL
      INSERT INTO officer_term_resignations (officer_term_id, left_on)
      SELECT id, left_on FROM officer_terms WHERE left_on IS NOT NULL
    SQL
    remove_column :memberships, :fee_amount
    remove_column :memberships, :fee_paid_on
    remove_column :officer_terms, :left_on
  end

  def down
    add_column :memberships, :fee_amount, :integer
    add_column :memberships, :fee_paid_on, :date
    add_column :officer_terms, :left_on, :date
    execute <<~SQL
      UPDATE memberships SET
        fee_amount = (SELECT amount FROM membership_fee_payments p WHERE p.membership_id = memberships.id),
        fee_paid_on = (SELECT paid_on FROM membership_fee_payments p WHERE p.membership_id = memberships.id)
    SQL
    execute <<~SQL
      UPDATE officer_terms SET
        left_on = (SELECT left_on FROM officer_term_resignations r WHERE r.officer_term_id = officer_terms.id)
    SQL
    drop_table :officer_term_resignations
    drop_table :membership_fee_payments
  end
end
