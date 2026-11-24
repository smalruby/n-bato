# 入会を認めた(イベント。日時は approved_at)。docs/adr/0030
# 人の記録(いなければ作る)と、その年度の正会員の資格を作る。申込のいまの状態(status など)を書き換える。
class MemberApplication::Approval < ApplicationRecord
  include EventRecord

  event_of :approved_at, entry: :approve!

  belongs_to :member_application
  belongs_to :approver, class_name: "User", optional: true
  belongs_to :person

  def self.approve!(application, fiscal_year:, joined_on:, by:, person: nil, at: Time.current)
    raise ArgumentError, "届いた申込ではありません" unless application.received?
    raise ArgumentError, "#{fiscal_year}年度は締めてあります。年度の締めを解いてから認めてください" if FiscalPeriod.for(fiscal_year)&.closed?

    a = application
    transaction do
      person ||= Person.create!(name: a.name, name_kana: a.name_kana, address: a.full_address, email: a.email, phone: a.phone)
      person.memberships.find_or_create_by!(fiscal_year:, kind: "regular") { it.joined_on = joined_on }
      approval = create!(member_application: a, approver: by, person:, fiscal_year:, joined_on:, approved_at: at)
      a.update!(status: "approved", person:, fiscal_year:, joined_on:, decided_on: at.to_date)
      Audit.final!("#{a.name}さんの入会を認めた(#{fiscal_year}年度の正会員)")
      approval
    end
  end
end
