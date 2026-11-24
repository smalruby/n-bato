require "test_helper"
require "open3"

# レビュー指摘のまとめコメント(lib/review_findings.rb・bin/review-findings)
class ReviewFindingsTest < ActiveSupport::TestCase
  def finding(category, text, location: nil, handling: nil)
    { "category" => category, "text" => text, "location" => location, "handling" => handling }.compact
  end

  def summary_comment(round, *ids, id: 100 + round)
    { "id" => id, "body" => ([ ReviewFindings.marker(round), "要約" ] + ids.map { "- **[#{it}]** 指摘" }).join("\n") }
  end

  test "1 回目は印・件数・分類ごとの見出しを出し、Must → Question → FYI の順に番号を振る" do
    body = ReviewFindings.render(round: 1, findings: [
      finding("FYI", "書き方を短くできる", location: "app/a.rb:3", handling: "修正済み(abc1234)"),
      finding("Must", "nil で落ちる", location: "app/b.rb:10", handling: "修正済み(def5678)"),
      finding("question", "名前が分かりにくい", handling: "人間の判断に委ねる: どちらの名前にするか"),
      finding("Must", "テストが無い")
    ])
    lines = body.lines(chomp: true)

    assert_equal "<!-- nbato-review-findings round=1 -->", lines[0]
    assert_equal "🤖 敵対的レビュー(round 1): 指摘 4 件(Must 2 / Question 1 / FYI 1)", lines[1]
    assert_equal [ "### Must", "### Question", "### FYI" ], lines.grep(/\A### /)
    assert_includes lines, "- **[M1]** `app/b.rb:10` nil で落ちる — 修正済み(def5678)"
    assert_includes lines, "- **[M2]** テストが無い"
    assert_includes lines, "- **[Q1]** 名前が分かりにくい — 人間の判断に委ねる: どちらの名前にするか"
    assert_includes lines, "- **[FYI1]** `app/a.rb:3` 書き方を短くできる — 修正済み(abc1234)"
    assert_match "Q1はOK, FYI1は修正して", body
  end

  test "指摘が無ければ「指摘なし。」だけで、返事の案内は出さない" do
    body = ReviewFindings.render(round: 2, findings: [ finding("Unknown", "捨てる") ])

    assert_equal "<!-- nbato-review-findings round=2 -->\n🤖 敵対的レビュー(round 2): 指摘なし。", body
  end

  test "2 回目は前の回の続きから番号を振る。人のコメントの番号は数えない" do
    comments = [ summary_comment(1, "M1", "Q1", "Q2"), { "id" => 1, "body" => "**[Q9]** を引用しただけ" } ]

    assert_equal 2, ReviewFindings.next_round(comments)
    assert_equal({ "Must" => 2, "Question" => 3, "FYI" => 1 }, ReviewFindings.next_numbers(comments))

    body, action = ReviewFindings.compose(comments:, findings: [ finding("Question", "もう 1 つ"), finding("FYI", "小さなこと") ])

    assert_equal "POST", action
    assert_match "round=2", body
    assert_match "**[Q3]** もう 1 つ", body
    assert_match "**[FYI1]** 小さなこと", body
  end

  test "同じ回をやり直すときは、そのコメントを書き換え、番号はその回の前の続きから振る" do
    comments = [ summary_comment(1, "M1"), summary_comment(2, "M2", "Q1", id: 555) ]

    body, action = ReviewFindings.compose(comments:, findings: [ finding("Must", "やり直し") ], round: 2)

    assert_equal "PATCH 555", action
    assert_match "**[M2]** やり直し", body
  end

  test "番号の表記のゆれを受ける" do
    assert_equal({ id: "Q1", category: "Question", number: 1 }, ReviewFindings.parse_id("question1"))
    assert_equal "M2", ReviewFindings.parse_id("Must2")[:id]
    assert_equal "FYI3", ReviewFindings.parse_id("F3")[:id]
    assert_equal "Q12", ReviewFindings.parse_id("Q１２")[:id]
    assert_nil ReviewFindings.parse_id("Q0")
    assert_nil ReviewFindings.parse_id("X1")
  end

  test "人の返事から番号ごとの指示を読む" do
    refs = ReviewFindings.parse_references(<<~TEXT).to_h { [ it[:id], it[:instruction] ] }
      > **[M1]** 修正済み(引用は読まない)
      Q1はOK, FYI1は修正して
      Q2, Q3は直して。M2は修正しなくていい
      FYI2 はなぜ?
      HTTP2 と AM1 は番号ではない
      Q4
    TEXT

    assert_equal({ "Q1" => :ok, "FYI1" => :fix, "Q2" => :fix, "Q3" => :fix, "M2" => :ok, "FYI2" => :other, "Q4" => :other }, refs)
  end

  test "後から言い直したら後のものを使う。まとめコメントに無い番号と、触れていない指摘は計画に入れない" do
    comments = [ summary_comment(1, "M1", "Q1", "FYI1") ]
    plan = ReviewFindings.plan(comments, [ "Q1は直して", "Q1はやっぱりOK。FYI1は直して。Q9は直して" ])

    assert_equal [ { "id" => "Q1", "category" => "Question", "action" => "no-change" },
                   { "id" => "FYI1", "category" => "FYI", "action" => "fix" } ], plan
  end

  test "bin/review-findings render は本文を書き、送り方を出す" do
    Dir.mktmpdir do |dir|
      File.write("#{dir}/comments.json", JSON.generate([ summary_comment(1, "M1", id: 42) ]))
      File.write("#{dir}/findings.json", JSON.generate([ finding("Must", "直す") ]))

      out, status = Open3.capture2(Rails.root.join("bin/review-findings").to_s, "render", "#{dir}/comments.json", "#{dir}/findings.json", "#{dir}/body.md")
      assert status.success?
      assert_equal "POST\n", out
      assert_match "**[M2]** 直す", File.read("#{dir}/body.md")

      out, = Open3.capture2({ "REVIEW_ROUND" => "1" }, Rails.root.join("bin/review-findings").to_s, "render", "#{dir}/comments.json", "#{dir}/findings.json", "#{dir}/body.md")
      assert_equal "PATCH 42\n", out
      assert_match "**[M1]** 直す", File.read("#{dir}/body.md")

      File.write("#{dir}/replies.json", JSON.generate([ "M1は修正して" ]))
      out, = Open3.capture2(Rails.root.join("bin/review-findings").to_s, "plan", "#{dir}/comments.json", "#{dir}/replies.json")
      assert_equal [ { "id" => "M1", "category" => "Must", "action" => "fix" } ], JSON.parse(out)

      _, err, status = Open3.capture3(Rails.root.join("bin/review-findings").to_s)
      assert_not status.success?
      assert_match "bin/review-findings render", err
    end
  end
end
