class Session < ApplicationRecord
  self.audited = false
  belongs_to :user
end
