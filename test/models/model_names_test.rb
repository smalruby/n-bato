require "test_helper"

# モデルの日本語の名前は config/locales/models.ja.yml にだけ書く(開発QAボード 第8回 8-6、#38)。
# 操作履歴の表示(AuditChange#model_label・summary)と、元に戻せないときの知らせ(Audit.check_states!)は model_name.human を読む。
class ModelNamesTest < ActiveSupport::TestCase
  # model_name_label に書いていた名前を、そのまま models.ja.yml に移した(ProcedureStep だけは、履歴の表示に出ていた「手順」のまま)
  NAMES = {
    "AnnualReport" => "事業報告", "AnnualReport::Milestone" => "事業報告の節目",
    "Consent" => "同意", "Consent::Cancellation" => "同意の取消",
    "IncomingRequest" => "依頼", "IncomingRequest::Settlement" => "依頼の解決",
    "IncomingRequestMessage" => "依頼の対話の発言", "IncomingRequestMessage::Adoption" => "AI の案を決めた",
    "IncomingRequestMessage::Delivery" => "依頼の対話を AI に送った",
    "MemberApplication::Approval" => "入会を認めた", "MemberApplication::Rejection" => "入会を認めなかった",
    "Person::AddressChange" => "住所の変更", "Person::NameChange" => "氏名の変更",
    "Person::ChangeCancellation" => "住所・氏名の出来事の取消", "PersonYear" => "会員・役員の年度の記録",
    "ProcedureRun" => "手続き", "ProcedureStep" => "手順", "ProcedureStep::StatusChange" => "手順の状態の変化",
    "RegistrationFiling" => "登記の申請", "RegistrationFiling::Submission" => "登記の申請(送った)",
    "RegistrationFiling::Acceptance" => "登記の申請の受付", "RegistrationFiling::Correction" => "登記の申請の補正",
    "RegistrationFiling::Withdrawal" => "登記の申請の取下げ", "RegistrationFiling::Completion" => "登記の完了",
    "Resolution" => "決議", "ResolutionItem::Application" => "議案の反映",
    "Todo" => "やること", "Todo::StatusChange" => "やることの状態の変化"
  }.freeze

  test "名前は models.ja.yml から読む" do
    NAMES.each do |klass, name|
      assert_equal name, klass.constantize.model_name.human, klass
      assert_equal name, I18n.t("activerecord.models.#{klass.underscore}"), "#{klass} が models.ja.yml に無い"
    end
  end

  test "操作履歴に残るモデルは、どれも models.ja.yml に名前がある(英語の名前を履歴に出さない)" do
    Rails.application.eager_load!
    missing = ApplicationRecord.descendants.reject(&:abstract_class?).select(&:audited)
      .reject { I18n.exists?("activerecord.models.#{it.model_name.i18n_key}", :ja) }.map(&:name)
    assert_empty missing
  end

  test "model_name_label は無い" do
    Rails.application.eager_load!
    assert_empty ApplicationRecord.descendants.select { it.respond_to?(:model_name_label) }.map(&:name)
  end

  test "操作履歴の表示に、日本語の名前が出る" do
    person = Person.create!(name: "会員　花子", address: "テスト市1")
    Audit.operation(user: users(:one), scope: "people") do
      Person::AddressChange.record!(person, address: "テスト市2", moved_on: Date.new(2025, 4, 1), by: users(:one))
    end
    assert_includes AuditOperation.order(:id).last.audit_changes.map(&:summary), "追加: 住所の変更"
  end

  test "住所の変更の取消の履歴の名前は、前と同じ" do
    person = Person.create!(name: "会員　花子", address: "テスト市1")
    change = Person::AddressChange.record!(person, address: "テスト市2", moved_on: Date.new(2025, 4, 1), by: users(:one))
    Audit.operation(user: users(:one), scope: "people") { Person::ChangeCancellation.cancel!(change, by: users(:one), reason: "打ち間違い") }
    assert_equal "会員　花子の住所の変更(2025/04/01)を取り消した: 打ち間違い", AuditOperation.order(:id).last.label
  end
end
