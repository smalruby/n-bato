# 事業報告書の、事業の区分ごとの実施内容。
class ProgramActivity < ApplicationRecord
  belongs_to :annual_report
  belongs_to :department

  def blank_activity? = schedule.blank? && beneficiaries.blank? && report.blank?
end
