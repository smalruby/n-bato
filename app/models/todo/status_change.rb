# やることの状態を変えた(イベント。日時は changed_at)。docs/adr/0034
# 作業中にした・待ちにした(誰の何を待つか)・済みにした(ひとこと)・未着手に戻した の 4 つを、変えたあとの状態で表す。
# 決まり(済みの決まり・待ちが解ける決まり)で変えたときは automatic。やることのいまの状態は、最後の変化から決まる。
# ふつうの操作なので、元に戻せる(元に戻すと、この変化も消え、やることは前の状態に戻る)。
class Todo::StatusChange < ApplicationRecord
  include EventRecord
  event_of :changed_at, entry: :change!

  belongs_to :todo
  belongs_to :changed_by, class_name: "User", optional: true

  validates :status, inclusion: { in: Todo::STATUSES.keys }

  def self.model_name_label = "やることの状態の変化"

  def status_label = Todo::STATUSES.fetch(status)

  # status: todo・doing・wait・done。waiting_on は待ちのとき、note は済みのときのひとこと(決まりで変えたときは理由)。
  # いまの状態と同じなら何もしない(nil を返す)。
  def self.change!(todo, status:, waiting_on: "", note: "", automatic: false, by: Current.user, at: Time.current)
    raise ArgumentError, "状態が分かりません" unless Todo::STATUSES.key?(status)

    change = new(todo:, status:, waiting_on: status == "wait" ? waiting_on.to_s.strip : "", note: note.to_s.strip,
                 automatic:, changed_by: automatic ? nil : by, changed_at: at)
    state = Todo.state_for(change)
    return if state.except("done_at") == todo.attributes.slice(*Todo::STATE_COLUMNS).except("done_at")

    transaction do
      # やることを先に書く(元に戻すの表示が「状態 未着手 → 作業中」になるように)
      todo.apply_state!(state)
      change.save!
      Audit.label!("やること「#{todo.title}」を#{todo.status_label}にした")
      change
    end
  end
end
