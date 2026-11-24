require "test_helper"

class OpsScriptTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class FakeSnapshot
    def create! = "production-20261124-180000.sqlite3"
  end

  def run_script(source, apply:)
    out = StringIO.new
    OpsScript.run!(source:, name: "2026-11-24-test.rb", apply:, out:, snapshot: FakeSnapshot.new)
    out.string
  end

  setup do
    User.where.not(id: users(:one).id).delete_all
    Todo.create!(title: "架空のやること")
  end

  test "試し流しは最後に巻き戻し、先頭に試し流しであることとスクリプトの名前を出す" do
    todo = Todo.first
    out = run_script(<<~RUBY, apply: false)
      Audit.operation(user: operator, scope: "todos", label: "試し") { Todo.find(#{todo.id}).update!(title: "試しの題") }
    RUBY
    assert_match "試し流し", out.lines.first
    assert_match "2026-11-24-test.rb", out
    assert_match "取らない", out
    assert_match "Todo update: 1", out
    assert_match "巻き戻した", out
    assert_not_equal "試しの題", todo.reload.title
  end

  test "本番流しは書き込み、書く前のバックアップの名前を先頭に出す" do
    todo = Todo.first
    out = run_script(%(Audit.operation(user: operator, scope: "todos", label: "本番") { Todo.find(#{todo.id}).update!(title: "本番の題") }), apply: true)
    assert_match "本番流し", out.lines.first
    assert_match "production-20261124-180000.sqlite3", out
    assert_equal "本番の題", todo.reload.title
  end

  test "例外になったら、それまでの変更も書かれない" do
    todo = Todo.first
    assert_raises(RuntimeError) do
      run_script(%(Todo.find(#{todo.id}).update!(title: "途中"); raise "止まった"), apply: true)
    end
    assert_not_equal "途中", todo.reload.title
  end

  test "試し流しではジョブを積まない" do
    assert_no_enqueued_jobs { run_script("SlackNoticeJob.perform_later", apply: false) }
  end

  test "ユーザーが 2 人以上なら operator は止まる" do
    assert_equal users(:one), OpsScript.operator
    User.create!(email_address: "second@example.com", password: "password-for-test-1")
    assert_raises(RuntimeError) { OpsScript.operator }
  end

  test "大きすぎるスクリプトは流さない" do
    assert_raises(ArgumentError) { run_script("#" * (OpsScript::MAX_BYTES + 1), apply: false) }
  end
end
