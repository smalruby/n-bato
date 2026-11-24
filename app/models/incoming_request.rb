# 外から届いた依頼(所轄庁のメールなど)。やることは、依頼ごとの AI との対話で作る(デザインシステム「やること」)。
# 長いイベント(docs/adr/0034)。「解決にした」は詳細のイベント IncomingRequest::Settlement。
# status・resolved_on は「いまの状態」で、IncomingRequest::Settlement.settle! だけが書き換える(照合は model:verify)。
# 題・相手・届いた日・期限・送付状の下書きは中身で、AI の案を決めたとき(IncomingRequestMessage::Adoption)などに直す。
class IncomingRequest < ApplicationRecord
  STATUSES = { "open" => "進行中", "resolved" => "解決" }.freeze
  STATE_COLUMNS = %w[status resolved_on].freeze

  has_many :todos, -> { order(:position, :id) }, dependent: :destroy
  has_many :messages, -> { order(:id) }, class_name: "IncomingRequestMessage", dependent: :restrict_with_error
  has_one :settlement, class_name: "IncomingRequest::Settlement", dependent: :restrict_with_error

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  validate :state_written_by_settlement

  scope :ordered, -> { order(Arel.sql("status = 'resolved', due_on IS NULL, due_on, id")) }

  def self.model_name_label = "依頼"

  def status_label = STATUSES.fetch(status)
  def resolved? = status == "resolved"
  def all_done? = todos.any? && todos.all?(&:done?)
  def done_count = todos.count(&:done?)
  def audit_fiscal_year = nil

  # いまの状態は「解決にした」があるかで決まる(docs/adr/0005)
  def derived_state = { "status" => settlement ? "resolved" : "open", "resolved_on" => settlement&.settled_on }

  # 下書きを消したあと、何も残っていない依頼は消してよい(まだ何も始まっていない)
  def discardable? = messages.none? && todos.none? && settlement.nil?

  # いまの状態の列を書き換える。呼ぶのは IncomingRequest::Settlement.settle! だけ。
  def apply_state!(state)
    @applying_state = true
    update!(state)
  ensure
    @applying_state = false
  end

  private

  def state_written_by_settlement
    return if @applying_state

    if new_record?
      errors.add(:base, "依頼は進行中で作ってください(解決は IncomingRequest::Settlement.settle!)") unless status == "open" && resolved_on.nil?
    elsif (changed = STATE_COLUMNS & changed_attribute_names_to_save).any?
      errors.add(:base, "#{changed.join('・')} は直接書き換えません。IncomingRequest::Settlement.settle!(依頼) を使ってください")
    end
  end
end
