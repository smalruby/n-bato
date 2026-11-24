require "test_helper"

# やること・依頼のイベント(docs/adr/0034)。データは架空。
class TodoEventsTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(json) = @json = json
    def complete_json(**) = @json
  end

  setup do
    @user = users(:one)
    @req = IncomingRequest.create!(title: "架空の依頼")
    @todo = @req.todos.create!(title: "架空のやること", fiscal_year: 2024, kind: "ask")
  end

  def op(&) = Audit.operation(user: @user, scope: "todos") { ApplicationRecord.transaction(&) }

  test "状態の変化から、いまの状態が決まる(待ち → 済み → 未着手)" do
    assert_equal "todo", @todo.status
    Todo::StatusChange.change!(@todo, status: "wait", waiting_on: " 監事の返事 ", by: @user)
    assert_equal [ "wait", "監事の返事" ], [ @todo.reload.status, @todo.waiting_on ]
    change = Todo::StatusChange.change!(@todo, status: "done", note: "出した", by: @user)
    @todo.reload
    assert_equal [ "done", "", "user", "出した" ], [ @todo.status, @todo.waiting_on, @todo.done_by, @todo.done_note ]
    assert_equal change.changed_at.to_i, @todo.done_at.to_i
    assert_equal @user, change.changed_by
    Todo::StatusChange.change!(@todo, status: "todo", by: @user)
    @todo.reload
    assert_equal [ "todo", nil, "", "" ], [ @todo.status, @todo.done_at, @todo.done_by, @todo.done_note ]
    assert_equal %w[wait done todo], @todo.status_changes.map(&:status)
    assert_empty ModelVerification.mismatches
  end

  test "いまの状態と同じなら変化を足さない。分からない状態は止める" do
    assert_nil Todo::StatusChange.change!(@todo, status: "todo")
    Todo::StatusChange.change!(@todo, status: "doing")
    assert_nil Todo::StatusChange.change!(@todo.reload, status: "doing")
    assert_equal 1, @todo.status_changes.count
    assert_raises(ArgumentError) { Todo::StatusChange.change!(@todo, status: "unknown") }
    assert_equal "作業中", @todo.status_changes.last.status_label
  end

  test "いまの状態の列は直接書き換えられない(中身は直せる)" do
    assert_raises(ActiveRecord::RecordInvalid) { @todo.update!(status: "done") }
    assert_raises(ActiveRecord::RecordInvalid) { Todo.create!(title: "x", status: "wait") }
    error = assert_raises(ActiveRecord::RecordInvalid) { @todo.reload.update!(done_note: "x") }
    assert_match "Todo::StatusChange.change!", error.message
    @todo.reload.update!(title: "直した題", due_on: Date.new(2026, 12, 1))
    assert_equal "直した題", @todo.reload.title
  end

  test "元に戻すと、状態の変化も消えて前の状態に戻る。やり直すと戻る" do
    op { Todo::StatusChange.change!(@todo, status: "done", note: "済んだ", by: @user) }
    assert @todo.reload.done?
    Audit.undo!(@user, "todos")
    assert_equal "todo", @todo.reload.status
    assert_empty @todo.status_changes
    assert_empty ModelVerification.mismatches
    Audit.redo!(@user, "todos")
    assert @todo.reload.done?
    assert_equal 1, @todo.status_changes.count
    assert_empty ModelVerification.mismatches
  end

  test "元に戻すの表示は、これまでどおりやることの状態の列の変化(イベントを先に出さない)" do
    op { Todo::StatusChange.change!(@todo, status: "doing", by: @user) }
    peek = Audit.peek(@user, "todos")[:undo]
    assert_match(/doing → todo/, peek[:detail])
    assert_equal "todo_#{@todo.id}", peek[:record]
  end

  test "決まりで済み・決まりで作業中に戻す(automatic)" do
    AnnualReport.create!(fiscal_year: 2024, submitted_on: Date.new(2026, 11, 24))
    @todo.update!(done_rule: "annual_report_submitted")
    Todo.refresh_auto!
    @todo.reload
    assert_equal [ "done", "auto" ], [ @todo.status, @todo.done_by ]
    assert @todo.status_changes.last.automatic
    assert_nil @todo.status_changes.last.changed_by

    other = Todo.create!(title: "待つもの", resume_rule: "registration_completed")
    Todo::StatusChange.change!(other, status: "wait", waiting_on: "登記")
    assert_equal [ other ], Todo.resume!("registration_completed", note: "登記が完了した")
    other.reload
    assert_equal [ "doing", "" ], [ other.status, other.waiting_on ]
    assert_match "登記が完了した", other.note
    assert_empty ModelVerification.mismatches
  end

  test "照合: 列を直接書き換えると食い違いが出る" do
    Todo::StatusChange.change!(@todo, status: "wait", waiting_on: "返事")
    @todo.update_columns(status: "done")
    assert_match(/やること ##{@todo.id}: status/, ModelVerification.todo_mismatches.join)
    @todo.update_columns(status: "wait", waiting_on: "別のもの")
    assert_match "waiting_on", ModelVerification.todo_mismatches.join
    Todo::StatusChange.change!(@todo.reload, status: "done", note: "済み")
    @todo.update_columns(done_by: "auto")
    assert_match "done_by", ModelVerification.todo_mismatches.join
  end

  test "依頼を解決にする(全部済んでから。force なら済んでいなくても)" do
    assert_raises(ArgumentError) { IncomingRequest::Settlement.settle!(@req) }
    s = IncomingRequest::Settlement.settle!(@req, force: true, by: @user, on: Date.new(2026, 11, 24))
    assert_equal [ "resolved", Date.new(2026, 11, 24) ], [ @req.reload.status, @req.resolved_on ]
    assert_equal @user, s.settled_by
    assert_raises(ArgumentError) { IncomingRequest::Settlement.settle!(@req.reload, force: true) }
    assert_raises(ActiveRecord::RecordInvalid) { @req.update!(status: "open") }
    assert_raises(ActiveRecord::RecordInvalid) { IncomingRequest.create!(status: "resolved") }
    assert_empty ModelVerification.mismatches
    @req.update_columns(resolved_on: nil)
    assert_match "依頼 ##{@req.id}", ModelVerification.incoming_request_mismatches.join
  end

  test "解決を元に戻すと、進行中に戻る" do
    Todo::StatusChange.change!(@todo, status: "done")
    Audit.operation(user: @user, scope: "incoming_requests") { IncomingRequest::Settlement.settle!(@req, by: @user) }
    assert @req.reload.resolved?
    Audit.undo!(@user, "incoming_requests")
    assert_equal [ "open", nil ], [ @req.reload.status, @req.resolved_on ]
    assert_nil @req.settlement
    assert_empty ModelVerification.mismatches
  end

  test "対話: 下書き → 送った(伏せた文と AI の返事)→ この案で決める" do
    draft = IncomingRequestMessage.write!(@req, role: "user", body: "架空の依頼の文")
    assert draft.draft?
    assert_equal [ draft ], @req.messages.drafts.to_a
    assert_equal "", draft.masked_body
    json = { "reply" => "わかりました", "request" => { "title" => "架空の依頼(整理済み)", "counterpart" => "", "received_on" => "2026-11-20", "due_on" => "bad" },
             "todos_new" => [ { "title" => "新しいやること", "fiscal_year" => 0, "kind" => "nope", "assignee" => "AI", "due_on" => "", "target" => "x", "done_rule" => "", "note" => "" } ],
             "todos_update" => [ { "id" => @todo.id, "status" => "wait", "waiting_on" => "相手の返事", "done_note" => "" }, { "id" => 0, "status" => "done" }, { "id" => @todo.id, "status" => "?" } ] }
    reply = Requests::Organizer.new(@req, client: FakeClient.new(json)).call(draft, masked_body: "伏せた文", send_attachments: true)
    draft.reload
    assert draft.sent?
    assert_not draft.draft?
    assert_equal [ "伏せた文", true ], [ draft.masked_body, draft.send_attachments ]
    assert_equal [ "assistant", "わかりました" ], [ reply.role, reply.body ]
    assert reply.proposal_actionable?
    assert_raises(ArgumentError) { IncomingRequestMessage::Delivery.deliver!(draft, masked_body: "", send_attachments: false, reply: json) }
    assert_raises(ArgumentError) { draft.discard! }

    assert_raises(ArgumentError) { IncomingRequestMessage::Adoption.adopt!(draft) }
    created, updated = IncomingRequestMessage::Adoption.adopt!(reply, by: @user)
    assert_equal 1, created.size
    assert_equal [ @todo ], updated
    assert_equal [ "screen", "", nil ], [ created.first.kind, created.first.target, created.first.fiscal_year ]
    @req.reload
    assert_equal [ "架空の依頼(整理済み)", Date.new(2026, 11, 20), nil ], [ @req.title, @req.received_on, @req.due_on ]
    assert_equal [ "wait", "相手の返事" ], [ @todo.reload.status, @todo.waiting_on ]
    assert reply.reload.applied?
    assert_not reply.proposal_actionable?
    assert_equal @user, reply.adoption.adopted_by
    assert_raises(ArgumentError) { IncomingRequestMessage::Adoption.adopt!(reply) }
    assert_empty ModelVerification.mismatches
  end

  test "下書きだけは消せる。PDF と画像のほかの添付は付けない" do
    pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4"), "application/pdf", original_filename: "a.pdf")
    csv = Rack::Test::UploadedFile.new(StringIO.new("a,b"), "text/csv", original_filename: "a.csv")
    draft = IncomingRequestMessage.write!(@req, role: "user", body: "下書き", files: [ pdf, csv ])
    assert_equal [ "a.pdf" ], draft.files.map { it.filename.to_s }
    draft.discard!
    assert_not IncomingRequestMessage.exists?(draft.id)
    assert_not @req.reload.discardable?, "やることがある依頼は残す"
    empty = IncomingRequest.create!
    assert empty.discardable?
  end
end
