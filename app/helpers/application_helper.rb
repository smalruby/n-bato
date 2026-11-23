module ApplicationHelper
  def yen(amount) = amount.nil? ? "" : number_with_delimiter(amount)

  # 左のメニューの 1 項目(AppShell)。開いている画面は aria-current="page"。
  # 左のメニューのページ(デザインシステム Nav、見直し第12回)。アイコン + 文字。count は [数, 説明, 黄色か] か nil。
  def nav_link(label, path, icon: nil, also: [], count: nil)
    active = current_page?(path) || (path != root_path && ([ path ] + also).any? { request.path.start_with?(it) })
    link_to path, "aria-current": (active ? "page" : nil) do
      badge = if count
        n, text, soon = count
        tag.span(class: [ "nb-nav-count", ("nb-nav-count--soon" if soon) ], title: text) { tag.span("#{text.delete_suffix("#{n} 件")}", class: "sr-only") + n.to_s + tag.span(" 件", class: "sr-only") }
      end
      safe_join([ (icon(icon, size: :sm) if icon), tag.span(label), badge ].compact)
    end
  end

  # 左のメニュー「やること」の数: 期限を過ぎたもの(赤)、なければ 7 日以内(黄)、どちらも 0 なら出さない。
  def nav_todo_count
    return unless Current.user

    @nav_todo_count ||= begin
      sum = TodoList.new(helpers: self).summary
      if sum["over"].positive? then [ sum["over"], "期限を過ぎた #{sum["over"]} 件", false ]
      elsif sum["week"].positive? then [ sum["week"], "7 日以内 #{sum["week"]} 件", true ]
      else false
      end
    end || nil
  end

  def wareki_date(date, zen: false) = Wareki.date(date, zen:)

  # 数字を全角にする(所轄庁の様式に合わせる)
  def zenkaku(text) = Wareki.zenkaku(text)

  def fiscal_year_wareki(year, zen: false)
    label = FiscalYear.new(year).wareki_label
    zen ? zenkaku(label) : label
  end

  # 事業報告書の本文など、人が書いた Markdown を HTML にする(生の HTML は使わない)
  def markdown(text)
    renderer = Redcarpet::Render::HTML.new(escape_html: true, hard_wrap: true)
    sanitize(Redcarpet::Markdown.new(renderer, tables: true, autolink: false).render(text.to_s),
             tags: %w[p br strong em ul ol li table thead tbody tr th td h4 h5 blockquote code], attributes: %w[style])
  end

  # 操作履歴に出す値。科目・部門などの ID は名前にする。
  def history_value(change, field, value)
    return "(空)" if value.blank?

    klass = change.auditable_class
    reflection = klass&.reflect_on_all_associations(:belongs_to)&.find { it.foreign_key == field }
    if reflection && !reflection.polymorphic?
      reflection.klass.find_by(id: value)&.to_s || value
    elsif value.is_a?(Integer) && field.match?(/amount/)
      yen(value)
    else
      value.to_s.truncate(40)
    end
  end

  # 右ペインの操作履歴(この画面の操作)
  def history_panel(scope = @undo_scope)
    turbo_frame_tag "history", src: history_path(scope:), loading: :lazy, data: { undo_target: "history" } do
      tag.p("読み込み中…", class: "nb-history-empty")
    end
  end
end
