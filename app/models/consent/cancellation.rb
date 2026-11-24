# 書面決議への同意の記録を取り消した(イベント。日時は cancelled_at)。docs/adr/0038
# 打ち間違い(日付・方法)のときは、取り消してから記録し直す。取り消した同意は、決議の成立に数えない。
class Consent::Cancellation < ApplicationRecord
  include EventRecord
  event_of :cancelled_at, entry: :cancel!

  belongs_to :consent
  belongs_to :cancelled_by, class_name: "User", optional: true

  def self.model_name_label = "同意の取消"

  def audit_fiscal_year = consent&.consented_on&.then { FiscalYear.for(it).year }

  def self.cancel!(consent, by: Current.user, at: Time.current)
    raise ArgumentError, "もう取り消してあります" if consent.cancelled?

    Audit.operation do
      transaction(requires_new: true) do
        cancellation = create!(consent:, cancelled_by: by, cancelled_at: at)
        Audit.label!("#{consent.person.name} さんの同意の記録を取り消した")
        cancellation
      end
    end
  rescue ActiveRecord::RecordNotUnique
    # 二度押しで、もう一方が先に取り消した(古い記録を読んでいた)。セーブポイントごと取り消してある
    raise ArgumentError, "もう取り消してあります"
  end
end
