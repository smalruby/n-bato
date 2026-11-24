# PR のレビュー指摘のまとめコメント(スキル nbato-review。.claude/skills/nbato-review/SKILL.md)。
# 1 回のレビューの指摘を 1 つのコメントにまとめ、Must / Question / FYI ごとに M1・Q1・FYI1 の番号を振る。
# 番号は同じ PR の回(round)をまたいで続ける。人の返事(「Q1はOK, FYI1は修正して」)から、番号ごとの指示も読む。
#
# smalruby3-editor の autopilot(tools/autopilot/src/phases.js の renderReviewFindingsComment・
# nextReviewFindingNumbers・nextReviewFindingsRound・parseFindingReferences・planAddressReview)を Ruby に写したもの。
# Rails に頼らない(bin/review-findings から require する)。
module ReviewFindings
  CATEGORIES = %w[Must Question FYI].freeze
  ID_PREFIX = { "Must" => "M", "Question" => "Q", "FYI" => "FYI" }.freeze

  MARKER_PREFIX = "<!-- nbato-review-findings"
  ROUND_RE = /<!--\s*nbato-review-findings\s+round=(\d+)\s*-->/
  # まとめコメントの中の番号つきの指摘(例: **[Q1]**)
  ID_MARKER_RE = /\*\*\[(M|Q|FYI)(\d+)\]\*\*/
  # 人の返事の中の番号。表記のゆれ(Question1・Must1・F1)を受け、前後が英数字なら番号とみなさない(HTTP2・AM1)
  REF_RE = /(?<![A-Za-z0-9])(must|question|fyi|m|q|f)(\d+)(?![A-Za-z0-9])/i
  REF_ALIAS = { "must" => "Must", "m" => "Must", "question" => "Question", "q" => "Question", "fyi" => "FYI", "f" => "FYI" }.freeze

  # 「直さなくてよい」を「直して」より先に見る(「修正しなくていい」を直す指示にしない)
  NO_FIX_RE = /(修正|変更|対応)(しなくて|せず|は?不要)|直さ(なくて|ず)|しないで/
  FIX_RE = /修正|直して|直す|なおして|(?<![a-z])fix(?![a-z])/i
  OK_RE = /(?<![a-z])(ok|lgtm)(?![a-z])|そのまま|問題な|了解|大丈夫|不要|スルー/i
  # 節の区切り。「.」は後ろが空白か終わりのときだけ(a.rb:3 のようなファイル名で割らない)
  CLAUSE_SPLIT_RE = /[,、。\n;!?]|\.(?=\s|$)/
  QUOTE_LINE_RE = /^\s*>/
  ID_ONLY_RE = /\A[\s・\/&+]*\z/

  module_function

  def marker(round) = "#{MARKER_PREFIX} round=#{round} -->"

  # コメントの本文からまとめコメントの回を読む。まとめコメントでなければ nil
  def round_of(body)
    m = body.to_s.match(ROUND_RE)
    m && m[1].to_i
  end

  # 次のレビューの回(いまある最大の回 + 1。無ければ 1)
  def next_round(comments)
    (comments.filter_map { round_of(it["body"]) }.max || 0) + 1
  end

  # その回のまとめコメント(やり直したときに二重に出さず、書き換えるため)
  def find_comment(comments, round)
    comments.find { round_of(it["body"]) == round }
  end

  # 番号の文字(Q1・q1・Question1・Must2・F3・全角の数字)を正しい形にする
  def parse_id(token)
    m = token.to_s.unicode_normalize(:nfkc).strip.match(/\A(must|question|fyi|m|q|f)(\d+)\z/i)
    return nil unless m

    category = REF_ALIAS[m[1].downcase]
    number = m[2].to_i
    return nil if number.zero?

    { id: "#{ID_PREFIX[category]}#{number}", category:, number: }
  end

  # まとめコメント(印のあるもの)の中の番号つきの指摘を、出てきた順に重ねずに集める。人のコメントは数えない
  def identified_findings(comments)
    comments.select { round_of(it["body"]) }.flat_map { it["body"].scan(ID_MARKER_RE) }
      .filter_map { |prefix, n| parse_id("#{prefix}#{n}") }.uniq { it[:id] }
  end

  # 次の回で使う、分類ごとの始めの番号(いまある最大の番号 + 1)
  def next_numbers(comments)
    start = CATEGORIES.to_h { [ it, 1 ] }
    identified_findings(comments).each { |f| start[f[:category]] = [ start[f[:category]], f[:number] + 1 ].max }
    start
  end

  def normalize_category(category) = CATEGORIES.find { it.casecmp?(category.to_s) }

  # 指摘を Must → Question → FYI に並べ、始めの番号から番号を振る。分類の中は渡された順。知らない分類は捨てる
  def assign_ids(findings, start = {})
    CATEGORIES.flat_map do |category|
      n = start[category] || 1
      findings.select { normalize_category(it["category"]) == category }.map do |f|
        f.merge("category" => category, "id" => "#{ID_PREFIX[category]}#{n}").tap { n += 1 }
      end
    end
  end

  def summary(counts)
    total = counts.values.sum
    return "指摘なし。" if total.zero?

    "指摘 #{total} 件(Must #{counts["Must"]} / Question #{counts["Question"]} / FYI #{counts["FYI"]})"
  end

  # 1 回のレビューのすべての指摘を、1 つのコメントの本文にする
  def render(round:, findings:, start: {})
    assigned = assign_ids(findings, start)
    counts = CATEGORIES.to_h { |c| [ c, assigned.count { it["category"] == c } ] }
    lines = [ marker(round), "🤖 敵対的レビュー(round #{round}): #{summary(counts)}" ]
    CATEGORIES.each do |category|
      group = assigned.select { it["category"] == category }
      next if group.empty?

      lines.push("", "### #{category}")
      group.each do |f|
        loc = f["location"].to_s.empty? ? "" : "`#{f["location"]}` "
        handling = f["handling"].to_s.empty? ? "" : " — #{f["handling"]}"
        lines << "- **[#{f["id"]}]** #{loc}#{f["text"]}#{handling}"
      end
    end
    unless assigned.empty?
      lines.push("", "直してほしい指摘は、番号で返事をください(例: `Q1はOK, FYI1は修正して`)。" \
        "返事をもらったら `/nbato-review address` で、その番号のものだけに対応します。")
    end
    lines.join("\n")
  end

  # まとめコメントの本文と、送り方(新しく出すか、その回のコメントを書き換えるか)を決める。
  # round を渡すと、その回をやり直す(書き換える)。渡さなければ次の回。
  def compose(comments:, findings:, round: nil)
    round ||= next_round(comments)
    existing = find_comment(comments, round)
    others = comments.reject { it.equal?(existing) }
    body = render(round:, findings:, start: next_numbers(others))
    [ body, existing ? "PATCH #{existing["id"]}" : "POST" ]
  end

  def classify_instruction(clause)
    return :ok if clause.match?(NO_FIX_RE)
    return :fix if clause.match?(FIX_RE)
    return :ok if clause.match?(OK_RE)

    :other
  end

  # 人の短い返事から、番号ごとの指示(:ok 直さない / :fix 直す / :other 質問・代案)を読む。
  # 句読点・カンマ・改行で節に分け、節の中の番号すべてにその節の指示を当てる。番号だけの節(「Q1, Q2は直して」の Q1)は
  # 次の指示のある節に合わせる。引用の行(>)は読まない。同じ番号が何度も出たら後のものを使う。
  def parse_references(text)
    by_id = {}
    apply = ->(ids, instruction) { ids.each { by_id[it[:id]] = it.slice(:id, :category).merge(instruction:) } }
    unquoted = text.to_s.unicode_normalize(:nfkc).lines.grep_v(QUOTE_LINE_RE).join
    pending = []
    unquoted.split(CLAUSE_SPLIT_RE).each do |clause|
      next if clause.strip.empty?

      ids = clause.scan(REF_RE).filter_map { |alias_, n| parse_id("#{alias_}#{n}") }
      next if ids.empty? && pending.empty?

      rest = clause.gsub(REF_RE, " ")
      if ids.any? && rest.match?(ID_ONLY_RE)
        pending.concat(ids)
        next
      end
      apply.call(pending + ids, classify_instruction(rest))
      pending = []
    end
    apply.call(pending.reject { by_id.key?(it[:id]) }, :other)
    by_id.values
  end

  ACTIONS = { ok: "no-change", fix: "fix", other: "reply" }.freeze

  # address のときの対応の計画。人が番号で触れた指摘だけを返す(触れなかった指摘は、レビューのときの扱いのまま)。
  # replies は人の返事の本文の配列(古い順。後のものを使う)。まとめコメントに無い番号は捨てる。
  def plan(comments, replies)
    refs = replies.flat_map { parse_references(it) }.to_h { [ it[:id], it ] }
    identified_findings(comments).filter_map do |f|
      ref = refs[f[:id]]
      ref && { "id" => f[:id], "category" => f[:category], "action" => ACTIONS.fetch(ref[:instruction]) }
    end
  end
end
