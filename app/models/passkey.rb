# パスキー(WebAuthn、見直し第14回)。1 人が複数持てる(パソコンとスマホなど)。
# 持つのは公開鍵と使った回数だけ。秘密の鍵は端末から出ない。足す・消すは元に戻せない操作として履歴に残す。
class Passkey < ApplicationRecord
  belongs_to :user

  validates :external_id, :public_key, presence: true
  validates :external_id, uniqueness: true
  validates :name, length: {maximum: 60}

  scope :ordered, -> { order(:created_at, :id) }

  def display_name = name.presence || "名前のないパスキー"
end
