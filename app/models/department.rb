class Department < ApplicationRecord
  include YearlyDataset
  ADMIN_CODE = 900
  validates :code, presence: true
  validates :name, presence: true
  scope :ordered, -> { order(:code) }

  def display_name = name.to_s.gsub(/[[:space:]]/, "")
  def admin? = code == ADMIN_CODE
  # 111〜119 = ①〜⑨事業
  def program_number = (111..119).cover?(code) ? code - 110 : nil
  def long_name = full_name.presence || display_name
  def to_s = display_name
end
