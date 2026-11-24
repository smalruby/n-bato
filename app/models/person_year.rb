# 会員・役員の、ある年度の記録(メール・電話・メモ)。メール・電話は暗号化する。
# 氏名・よみ・住所は年度ごとではなく、記録の始まりと日付つきの出来事で持つ(docs/adr/0029)。
class PersonYear < ApplicationRecord
  encrypts :email, :phone
  belongs_to :person, inverse_of: :person_years
  validates :fiscal_year, presence: true, uniqueness: {scope: :person_id}
  after_save { person.sync_latest!(self) }
end
