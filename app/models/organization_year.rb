# 法人の、ある年度の記録(法人名・所在地・代表者など)。
class OrganizationYear < ApplicationRecord
  belongs_to :organization, inverse_of: :organization_years
  validates :fiscal_year, presence: true, uniqueness: { scope: :organization_id }
  after_save { organization.sync_latest!(self) }
end
