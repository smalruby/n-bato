# 仕訳 1 行(借方・貸方とも 1 科目)。会計王 SIWAKE の 1 行と対応する。
class JournalEntry < ApplicationRecord
  SIDES = %w[debit credit].freeze
  SIDE_ATTRS = %i[sub_code sub_name tax_category_code business_category_code tax_treatment_code tax_rate amount tax_amount].freeze

  belongs_to :siwake_import, optional: true
  belongs_to :debit_account, class_name: "Account"
  belongs_to :credit_account, class_name: "Account"
  belongs_to :debit_department, class_name: "Department", optional: true
  belongs_to :credit_department, class_name: "Department", optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  # AI の提案を承認してできた仕訳なら、その承認(イベント)。承認でできた仕訳は消さない(訂正は訂正の仕訳。docs/adr/0007)
  has_one :proposal_approval, class_name: "JournalProposal::Approval", dependent: :restrict_with_error
  has_one :journal_proposal, through: :proposal_approval
  # 取消(イベント。docs/adr/0026)。取り消した仕訳は帳簿から外す
  has_one :cancellation, class_name: "JournalEntry::Cancellation", dependent: :restrict_with_error

  validates :entry_date, presence: true
  validates :debit_amount, :credit_amount, numericality: { only_integer: true }
  validate :amounts_balance

  before_validation { self.fiscal_year = FiscalYear.for(entry_date).year if entry_date }
  before_validation :use_accounts_of_year
  validate :accounts_in_year
  validate :debit_and_credit_differ

  scope :in_fiscal_year, ->(year) { where(fiscal_year: year) }
  # 帳簿に数える仕訳(取り消した仕訳を除く)
  scope :active, -> { where.not(id: Cancellation.select(:journal_entry_id)) }
  scope :cancelled, -> { where(id: Cancellation.select(:journal_entry_id)) }
  scope :chronological, -> { order(:entry_date, :slip_number, :line_number, :id) }

  def amount = debit_amount

  # 画面の入力では金額を 1 つだけ受け取り、借方・貸方の両方に入れる。
  def amount=(value)
    self.debit_amount = self.credit_amount = value.to_s.delete(",").presence&.to_i
  end

  # 会計王から取り込んだ仕訳は会計王が正なので、このアプリでは変更しない。
  def imported? = siwake_import_id.present?
  # 表で書き換え・削除できるか。会計王から取り込んだ仕訳、承認でできた仕訳(記帳したもの)、取り消した仕訳は直さない(docs/adr/0007・0026)
  def editable? = !imported? && proposal_approval.nil? && !cancelled?
  def cancelled? = cancellation.present?
  # 取り消せるか(会計王から取り込んだ仕訳は会計王で直す)
  def cancellable? = !imported? && !cancelled?

  before_create :assign_slip_number, unless: :slip_number?
  def fiscal_year_object = FiscalYear.new(fiscal_year)

  # 費用の仕訳の部門(事業区分)。
  def department_for(account) = account == debit_account ? debit_department : credit_department

  def self.from_siwake_row(row, accounts:, departments:)
    attrs = { slip_number: row.slip_number, line_number: row.line_number, entry_date: row.entry_date,
              summary: row.summary, sub_summary: row.sub_summary, memo: row.memo, tag1: row.tag1, tag2: row.tag2 }
    SIDES.each do |side|
      attrs[:"#{side}_account"] = accounts.fetch(row[:"#{side}_account_code"])
      dept_code = row[:"#{side}_department_code"]
      attrs[:"#{side}_department"] = dept_code.zero? ? nil : departments.fetch(dept_code)
      SIDE_ATTRS.each { |a| attrs[:"#{side}_#{a}"] = row[:"#{side}_#{a}"] }
    end
    new(attrs)
  end

  def to_siwake_row
    attrs = { slip_number: slip_number.to_i, line_number: line_number, entry_date: entry_date,
              summary: summary, sub_summary: sub_summary, memo: memo, tag1: tag1, tag2: tag2 }
    SIDES.each do |side|
      account = public_send(:"#{side}_account")
      department = public_send(:"#{side}_department")
      attrs[:"#{side}_account_code"] = account.code
      attrs[:"#{side}_account_name"] = account.name
      attrs[:"#{side}_department_code"] = department&.code || 0
      attrs[:"#{side}_department_name"] = department&.name || ""
      SIDE_ATTRS.each { |a| attrs[:"#{side}_#{a}"] = public_send(:"#{side}_#{a}") }
    end
    Kaikeiou::SiwakeFile::Row.new(**attrs)
  end

  private

  def assign_slip_number
    self.slip_number = (JournalEntry.where(fiscal_year: fiscal_year).maximum(:slip_number) || 0) + 1
  end

  def amounts_balance
    errors.add(:credit_amount, "は借方金額と同じにしてください") if debit_amount != credit_amount
  end

  # 科目・部門は年度ごとのデータセット。日付の年度が変わったら、その年度の同じコードの科目・部門に付け替える。
  def use_accounts_of_year
    return unless fiscal_year

    %i[debit_account credit_account debit_department credit_department].each do |assoc|
      record = public_send(assoc)
      next if record.nil? || record.fiscal_year == fiscal_year

      public_send(:"#{assoc}=", record.in_year(fiscal_year) || record)
    end
  end

  # 借方と貸方が同じ科目の仕訳は意味をなさない(画面の選び間違いを記帳しないため)
  def debit_and_credit_differ
    return unless debit_account && credit_account && debit_account.code == credit_account.code && debit_department&.code == credit_department&.code

    errors.add(:base, "借方と貸方が同じ科目です(#{debit_account.code} #{debit_account.display_name})。科目を選び直してください")
  end

  def accounts_in_year
    return unless fiscal_year

    %i[debit_account credit_account debit_department credit_department].each do |assoc|
      record = public_send(assoc)
      next if record.nil? || record.fiscal_year == fiscal_year

      errors.add(assoc, "が #{fiscal_year}年度にありません(#{record.code} #{record.display_name})")
    end
  end
end
