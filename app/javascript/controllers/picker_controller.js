import { Controller } from "@hotwired/stimulus"

// 一覧から選んで入れるセル(デザインシステム Picker)。長いドロップダウンの代わり。
// コード(「100」)か名前の一部(「消耗」)で絞り込む。↑↓ で選び、Enter で決める。決めたら隠し欄に change を送る(autosave が保存する)。
// 候補は <script type="application/json" id="picker-<source>"> の [{id, code, name}]。最初はこれまでの仕訳で使ったものだけで、
// 一覧のいちばん下の「すべての科目を出す」を選ぶと、data-url から残りも含めた一覧を取りに行く(全件を最初から画面に入れない)。
const norm = (s) => String(s || "").normalize("NFKC").toLowerCase().replace(/[ァ-ヶ]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0x60)).replace(/\s/g, "")

export default class extends Controller {
  static targets = ["text", "value"]
  static values = { source: String }

  disconnect() { this.close() }

  get source() { return document.getElementById(`picker-${this.sourceValue}`) }

  get items() {
    const el = this.source
    if (!el) return []
    if (!el._items) el._items = this.prepare(JSON.parse(el.textContent))
    return el._items
  }

  prepare(list) { return list.map((it) => ({ ...it, label: it.code ? `${it.code} ${it.name}` : it.name, key: norm(`${it.code} ${it.name} ${it.hint || ""}`) })) }

  // 隠している候補の数(0 なら全部出している)
  get hidden() {
    const el = this.source
    if (!el || el._complete) return 0
    return Math.max(Number(el.dataset.total || 0) - this.items.length, 0)
  }

  async loadAll() {
    const el = this.source
    if (!el || el._complete || !el.dataset.url) return
    this.showLoading()
    try {
      const res = await fetch(el.dataset.url, { headers: { "Accept": "application/json" } })
      const data = await res.json()
      el._items = this.prepare(data.items)
      el._complete = true
    } catch {
      this.showLoading("読み込めませんでした。もう一度選んでください")
      return
    }
    this.textTarget.focus()
    this.filter()
  }

  showLoading(text = "読み込んでいます") {
    const li = this.list?.querySelector("li.nb-picker-more")
    if (li) li.textContent = text
  }

  focus() { this.textTarget.select() }

  // 開いたときは全部を出し、いまの値の行を選んだ状態にする(一覧はスクロールできる)
  open() {
    this.render(this.items)
    const current = this.hits.findIndex((it) => String(it.id) === this.valueTarget.value)
    if (current >= 0) { this.index = current; this.mark() }
  }

  filter() {
    const q = norm(this.textTarget.value)
    const hits = q ? this.items.filter((it) => it.code.startsWith(q) || it.key.includes(q)) : this.items
    this.render(hits)
  }

  render(hits) {
    this.hits = hits
    const hidden = this.hidden
    // いちばん下の「すべてを出す」も ↑↓ で選べる行にする(this.hits の最後に印を付けて足す)
    if (hidden) this.hits = [ ...hits, { more: true } ]
    this.index = hits.length ? 0 : (hidden ? this.hits.length - 1 : -1)
    if (!this.list) {
      this.list = document.createElement("ul")
      this.list.className = "nb-picker-list"
      this.list.setAttribute("role", "listbox")
      this.list.addEventListener("mousedown", (e) => {
        e.preventDefault()
        const li = e.target.closest("li[data-i]")
        if (li) this.choose(this.hits[Number(li.dataset.i)])
      })
      document.body.append(this.list)
    }
    const noun = this.source?.dataset.noun || "候補"
    const rows = this.hits.map((it, i) => {
      const li = document.createElement("li")
      li.dataset.i = i
      li.setAttribute("role", "option")
      if (it.more) {
        li.className = "nb-picker-more"
        li.textContent = hits.length ? `すべての${noun}を出す(ほか ${hidden} 件)` : `すべての${noun}から探す(ほか ${hidden} 件)`
        return li
      }
      const code = document.createElement("span"); code.className = "nb-num"; code.textContent = it.code
      const name = document.createElement("span"); name.textContent = it.name
      li.append(code, name)
      if (it.hint) { const hint = document.createElement("span"); hint.className = "nb-picker-hint"; hint.textContent = it.hint; li.append(hint) }
      return li
    })
    if (!hits.length) rows.unshift(Object.assign(document.createElement("li"), { className: "is-empty", textContent: "当てはまるものがありません" }))
    this.list.replaceChildren(...rows)
    this.mark()
    const r = this.textTarget.getBoundingClientRect()
    const below = window.innerHeight - r.bottom
    this.list.style.left = `${r.left}px`
    this.list.style.minWidth = `${Math.max(r.width, 220)}px`
    if (below < 220) { this.list.style.top = ""; this.list.style.bottom = `${window.innerHeight - r.top}px` }
    else { this.list.style.bottom = ""; this.list.style.top = `${r.bottom}px` }
  }

  mark() {
    if (!this.list) return
    this.list.querySelectorAll("li[data-i]").forEach((li) => li.setAttribute("aria-selected", String(Number(li.dataset.i) === this.index)))
    this.list.querySelector('[aria-selected="true"]')?.scrollIntoView({ block: "nearest" })
  }

  key(event) {
    if (!this.list) {
      if (event.key === "ArrowDown" && event.altKey) { event.preventDefault(); event.stopPropagation(); this.open() }
      return
    }
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault(); event.stopPropagation()
      const n = this.hits.length
      if (n) { this.index = (this.index + (event.key === "ArrowDown" ? 1 : -1) + n) % n; this.mark() }
    } else if (event.key === "Enter") {
      if (this.index < 0) { event.preventDefault(); event.stopPropagation(); return }   // 当てはまらないときは保存も移動もしない
      if (this.hits[this.index]?.more) { event.preventDefault(); event.stopPropagation() }
      this.choose(this.hits[this.index])
    } else if (event.key === "Escape") {
      this.close()
    } else if (event.key === "Tab") {
      const it = this.hits[this.index]
      if (it && !it.more && norm(this.textTarget.value) !== norm(this.textTarget.dataset.original)) this.choose(it)
      else this.close()
    }
  }

  choose(item) {
    if (!item) return
    if (item.more) { this.loadAll(); return }
    this.textTarget.value = item.label
    this.textTarget.dataset.original = item.label
    this.textTarget.closest("td")?.classList.remove("is-dirty")
    this.close()
    if (this.valueTarget.value !== String(item.id)) {
      this.valueTarget.value = item.id
      this.valueTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }
  }

  blur() {
    setTimeout(() => {
      this.close()
      // 決めずに離れたら、元の表示に戻す
      if (this.textTarget.dataset.original !== undefined && this.textTarget.value !== this.textTarget.dataset.original) {
        this.textTarget.value = this.textTarget.dataset.original
        this.textTarget.closest("td")?.classList.remove("is-dirty")
      }
    }, 120)
  }

  close() { this.list?.remove(); this.list = null }
}
