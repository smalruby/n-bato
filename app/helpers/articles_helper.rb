# 定款の条文への参照(デザインシステム ArticleRef、見直し第13回)。
module ArticlesHelper
  REF = /定款[[:space:]]*((?:第[0-9０-９]+条(?:第[0-9０-９]+項)?(?:[（(][^）)]*[）)])?[・、]?)+)/

  # 文の中の「定款第○条」「定款 第49条・第50条」を、右ペインに条文を出すリンクにする。year はその年度の時点の版を出すため。
  def link_articles(text, year: Current.working_year)
    return text if text.blank?

    out = []
    rest = text.to_s
    while (m = REF.match(rest))
      out << m.pre_match << m[0][/\A定款[[:space:]]*/]
      out << m[1].split(/(第[0-9０-９]+条)/).map do |part|
        no = part[/\A第([0-9０-９]+)条\z/, 1]
        no ? link_to(part, article_path(Articles::Document.number(no), year:), class: "nb-artref", data: { turbo_frame: "article_ref" }) : part
      end
      rest = m.post_match
    end
    out << rest
    safe_join(out.flatten)
  end

  # 前の版との違いを、消した文・足した文で出す
  def article_change(before, after)
    safe_join([ (tag.del(before) if before), (tag.ins(after) if after) ].compact)
  end
end
