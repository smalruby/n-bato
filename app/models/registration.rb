# 法務局への登記。代表権のある理事(定款で決める。既定は理事長・副理事長)の就任・重任は 2 週間以内に変更登記する。
class Registration < ApplicationRecord
  KINDS = { "representative_change" => "理事の変更（重任・就任）登記", "other" => "その他の登記" }.freeze
  DEADLINE_DAYS = 14

  belongs_to :officer_term, optional: true
  validates :kind, inclusion: { in: KINDS.keys }
  validates :cause_on, :due_on, presence: true

  scope :pending, -> { where(registered_on: nil) }

  def kind_label = KINDS[kind]
  def done? = registered_on.present?
end
