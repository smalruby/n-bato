# やること(デザインシステム TodoList / RequestThread)の表示
module TodosHelper
  def year_chip(year)
    return tag.span("年度なし", class: "nb-ychip is-none") unless year

    hue = FiscalPeriod.hue(year)
    short = year >= 2019 ? "R#{year == 2019 ? '元' : year - 2018}" : "H#{year - 1988}"
    tag.span(class: "nb-ychip", style: "--year-ink:var(--year-#{hue}-ink);--year-fill:var(--year-#{hue}-fill)", title: FiscalYear.new(year).wareki_label) do
      safe_join([ year.to_s, " ", tag.small(short) ])
    end
  end

  def todo_status_tag(status)
    tag.span(Todo::STATUSES.fetch(status), class: "nb-st nb-st--#{status}")
  end

  # 伏せた箇所(【伏せた住所】など)を nb-mask で見せる
  def with_masks(text)
    parts = text.to_s.split(/(【伏せた[^】]+】)/)
    safe_join(parts.map { it.start_with?("【伏せた") ? tag.span(it.delete("【】"), class: "nb-mask") : it })
  end
end
