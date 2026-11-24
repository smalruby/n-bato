# カバレッジ: COVERAGE=1 bin/rails test(結果は coverage/。git 管理外)。対象はバックエンドのコード(ビューと JavaScript は対象外。docs/adr/0025)
#
# アプリを読み込む前に測り始める。config/boot.rb から読む(COVERAGE があるときだけ)。
# bin/rails test を引数なしで流すと、テストのファイルより先に test:prepare(tailwindcss:build → environment)が
# アプリを読み込む。test_helper で測り始めると、そのとき読み込んだファイル(イニシャライザが使う LocalMailbox、
# CI で eager_load するときはアプリのすべて)が測れず 0% になる(issue #6)。
#
# 並列のテスト(parallelize)は、rails のプロファイルの merge_subprocesses で、フォークした子ごとに測ってまとめる
# (子の結果は Minitest (subprocess: N) の名前で残る。parallelize_setup・teardown での手当ては要らない)。
# 100% を下回ると失敗にする(終了コードが 0 でなくなる)。一部のファイルだけ流すときは COVERAGE を付けない。
#
# 測る前に、前の回の結果(coverage/.resultset.json)を消す。残っていると、並列の子の古い結果がまとめに足され、
# 一部しか流していないのに 100% と出る。消すのは測り始める親のプロセスだけ(並列の子は boot.rb を読み直さない)。
# テストから bin/rails を子のプロセスで起こすときは、子に COVERAGE を渡さない({ "COVERAGE" => nil }。
# 渡すと子も測り、この結果を消して書き直してしまう。test/integration/demo_environment_test.rb)。
require "fileutils"
require "simplecov"

FileUtils.rm_f(File.expand_path("../coverage/.resultset.json", __dir__))

SimpleCov.start "rails" do
  skip %w[/test/ /config/ /db/ /vendor/ /lib/tasks/ /app/views/ /app/javascript/ /app/assets/]
  minimum_coverage line: 100
end
