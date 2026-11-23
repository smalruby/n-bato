# ブラウザの「戻る」を使わなくてよい画面(デザインシステム「行き来の決まり」、見直し第21回、docs/adr/0033)。
module NavigationHelper
  NEW_TAB_MARK = " ↗".freeze

  # 詳しい画面の題の上に出すパンくず。trail は [文字, パス] の並びで、最後はいまの画面の名前(文字だけ)。
  # 一覧へのパスは、その一覧で最後に開いた絞り込み・並べ替えの URL にする(remember_list_url)。
  def crumbs(*trail)
    *ups, here = trail
    content_for :crumbs do
      tag.nav(class: "nb-crumb", "aria-label": "いまの場所") do
        parts = ups.map { |label, path| link_to(label, remembered_list_url(path)) }
        safe_join(parts + [ tag.span(here, "aria-current": "page") ], tag.span("›", class: "nb-crumb-sep", "aria-hidden": "true"))
      end
    end
  end

  # 一覧の URL に、最後に見た絞り込みの状態(クエリ)を付けて返す。
  def remembered_list_url(path)
    (session[:list_urls] || {})[path.to_s] || path
  end

  # Nばとが返す PDF と外のサイトは、別のタブで開く(↗ を付ける)。
  def new_tab_link_to(label, path, **options)
    link_to(path, target: "_blank", rel: "noopener", title: options.delete(:title) || "別のタブで開く", **options) do
      safe_join([ label, NEW_TAB_MARK ])
    end
  end
end
