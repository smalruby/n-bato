# 会計王 SIWAKE ファイルの取り込み 1 回分。元のヘッダ行と列名行を保存し、同じ形で書き戻せるようにする。
class SiwakeImport < ApplicationRecord
  self.audited = false
  has_many :journal_entries, -> { order(:position) }, dependent: :destroy
  validates :filename, :sha256, :header_line, :columns_line, presence: true
  validates :sha256, uniqueness: {message: "の同じファイルはすでに取り込んでいます"}

  def to_siwake_file
    Kaikeiou::SiwakeFile.new(
      rows: journal_entries.includes(:debit_account, :credit_account, :debit_department, :credit_department).map(&:to_siwake_row),
      header_line: header_line, columns_line: columns_line
    )
  end
end
