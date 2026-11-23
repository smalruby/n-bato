class Session < ApplicationRecord
  self.audited = false
  belongs_to :user

  # パスキーを足す・消す前に、本人をもう一度確かめる間隔(見直し第14回)
  REVERIFY_AFTER = 10.minutes

  def verified_recently?(now = Time.current) = (verified_at || created_at) > now - REVERIFY_AFTER
  def verified!(now = Time.current) = update!(verified_at: now)
end
