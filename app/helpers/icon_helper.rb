# アイコン(デザインシステム Icon)。Lucide の SVG を app/assets/icons/lucide/ に置き、ここで埋め込む。
# 名前は「使う場面」で呼ぶ(icon(:undo))。アイコンには必ず文字を添え、アイコンだけのボタンは作らない。
module IconHelper
  ICONS = {
    undo: "undo", redo: "redo", add: "plus", delete: "trash-2", filter: "filter", search: "search",
    history: "history", saved: "check", saving: "loader-circle", warning: "triangle-alert", closed: "lock",
    year: "calendar", move: "arrow-right-left", expand: "chevron-down", procedure: "list-checks",
    document: "file-text", export: "download", voucher: "receipt-japanese-yen", yen: "japanese-yen",
    ledger: "book-open", people: "users", home: "house", info: "info", settings: "settings",
    role_clerk: "pencil", role_auditor: "eye",
    todo: "list-todo", accounting: "calculator", resolution: "gavel", registration: "landmark", accounts: "tags", organization: "building-2", passkey: "key-round",
    articles: "scroll-text"
  }.freeze
  SIZES = { md: 16, sm: 14 }.freeze

  def icon(role, size: :md)
    file = ICONS.fetch(role)
    px = SIZES.fetch(size)
    tag.svg(icon_paths(file), class: "nb-icon", width: px, height: px, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
            "stroke-width": 1.75, "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": true, focusable: false)
  end

  private

  def icon_paths(file)
    @@icon_cache ||= {}
    @@icon_cache[file] ||= begin
      svg = Rails.root.join("app/assets/icons/lucide/#{file}.svg").read
      svg[/<svg[^>]*>(.*)<\/svg>/m, 1].gsub(/\s+/, " ").strip.html_safe
    end
  end
end
