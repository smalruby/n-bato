# 書面決議への同意(書面または電子メール)。
class Consent < ApplicationRecord
  VIAS = { "paper" => "書面", "email" => "電子メール" }.freeze
  belongs_to :resolution
  belongs_to :person
  validates :consented_on, presence: true
  validates :via, inclusion: { in: VIAS.keys }
  validates :person_id, uniqueness: { scope: :resolution_id }
  def via_label = VIAS[via]
end
