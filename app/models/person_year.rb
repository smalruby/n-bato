# 会員・役員の、ある年度の記録(氏名・よみ・住所・メール・電話・メモ)。住所・メール・電話は暗号化する。
class PersonYear < ApplicationRecord
  encrypts :address, :email, :phone
  belongs_to :person, inverse_of: :person_years
  validates :name, presence: true
  validates :fiscal_year, presence: true, uniqueness: { scope: :person_id }
  after_save { person.sync_latest!(self) }

  def self.model_name_label = "会員・役員の年度の記録"
end
