# 登記の申請(長いイベント)。1 件の申請に、重任・住所の変更・氏名の変更などの登記の事由をまとめる。docs/adr/0031
# 手順: 何を登記するか → 書類を作る → 申請した(申請番号) → 受付(受付番号) → 補正(あれば) → 完了。
# 申請した・受付・補正・完了・取下げは詳細のイベント。いまの状態(status)はイベントから決まり、入口だけが書き換える(照合は model:verify)。
class RegistrationFiling < ApplicationRecord
  STATUSES = {"drafting" => "書類を作っている", "submitted" => "申請した", "accepted" => "受け付けられた",
              "correcting" => "補正を求められた", "completed" => "完了した", "withdrawn" => "取り下げた"}.freeze
  STEPS = [["items", "何を登記するか"], ["documents", "書類を作る"], ["submitted", "申請した"],
    ["accepted", "受付"], ["correcting", "補正(あれば)"], ["completed", "完了"]].freeze

  has_many :registrations, -> { order(:cause_on, :id) }, dependent: :nullify
  belongs_to :general_meeting_resolution, class_name: "Resolution", optional: true
  belongs_to :board_resolution, class_name: "Resolution", optional: true
  has_one :submission, class_name: "RegistrationFiling::Submission", dependent: :restrict_with_error
  has_one :acceptance, class_name: "RegistrationFiling::Acceptance", dependent: :restrict_with_error
  has_many :corrections, -> { order(:noticed_on, :id) }, class_name: "RegistrationFiling::Correction", dependent: :restrict_with_error
  has_one :completion, class_name: "RegistrationFiling::Completion", dependent: :restrict_with_error
  has_one :withdrawal, class_name: "RegistrationFiling::Withdrawal", dependent: :restrict_with_error

  validates :status, inclusion: {in: STATUSES.keys}

  scope :recent, -> { order(id: :desc) }

  def self.model_name_label = "登記の申請"

  def status_label = STATUSES[status]
  def drafting? = status == "drafting"
  def withdrawn? = status == "withdrawn"
  def completed? = status == "completed"
  def finished? = completed? || withdrawn?

  def derived_status
    if withdrawal then "withdrawn"
    elsif completion then "completed"
    elsif corrections.any? then "correcting"
    elsif acceptance then "accepted"
    elsif submission then "submitted"
    else "drafting"
    end
  end

  def advance_status! = update!(status: derived_status)

  # 申請を始める(書類を作る段階から)。選んだ登記の事由をまとめる。
  def self.start!(registrations, note: "")
    regs = Array(registrations)
    raise ArgumentError, "登記することを 1 つ以上選んでください" if regs.empty?
    raise ArgumentError, "すでに登記したか、ほかの申請に入っているものがあります" unless regs.all?(&:available?)

    transaction do
      filing = create!(note:)
      regs.each { it.update!(registration_filing: filing) }
      Audit.label!("登記の申請を始めた(#{regs.map(&:kind_label).uniq.join("・")})")
      filing
    end
  end

  # 書類を作っている間だけ、登記することを足したり外したりできる
  def include!(registration)
    raise ArgumentError, "申請したあとは、登記することを変えられません" unless drafting?
    raise ArgumentError, "すでに登記したか、ほかの申請に入っています" unless registration.available?

    registration.update!(registration_filing: self)
  end

  def exclude!(registration)
    raise ArgumentError, "申請したあとは、登記することを変えられません" unless drafting?

    registration.update!(registration_filing: nil) if registration.registration_filing_id == id
  end

  # 手順の札(画面): 済み・いま・まだ
  def step_state(key)
    order = %w[items documents submitted accepted correcting completed]
    now = case status
    when "drafting" then registrations.any? ? "documents" : "items"
    when "submitted" then "accepted"
    when "accepted" then "completed"
    when "correcting" then "correcting"
    else "done"
    end
    return :done if now == "done" || (key == "correcting" && corrections.any? && status != "correcting")
    return :skip if key == "correcting" && corrections.none?

    i = order.index(key)
    n = order.index(now)
    if i < n
      :done
    else
      ((i == n) ? :now : :todo)
    end
  end

  def statement = RegistrationFiling::Statement.new(self)
end
