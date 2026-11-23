import { Controller } from "@hotwired/stimulus"

// 表の下の集計(デザインシステム SheetFooter)。選んだ行(tr.is-selected-row の data-amount)から合計などを出す。
// 出すものは「▾ 出すものを選ぶ」で選び、人ごと・画面ごとにこのブラウザに覚える。
const DEFAULT = ["count", "sum"]
const yen = (n) => Math.round(n).toLocaleString("ja-JP")

export default class extends Controller {
  static targets = ["bar", "count", "sum", "stats", "menu", "menuButton"]
  static values = { key: String }

  connect() {
    this.shown = this.load()
    this.menuTarget.querySelectorAll("input").forEach((i) => { i.checked = this.shown.includes(i.value) })
    this.update()
  }

  load() {
    try { return JSON.parse(localStorage.getItem(`nb-foot:${this.keyValue}`)) || DEFAULT } catch { return DEFAULT }
  }

  choose() {
    this.shown = [...this.menuTarget.querySelectorAll("input:checked")].map((i) => i.value)
    try { localStorage.setItem(`nb-foot:${this.keyValue}`, JSON.stringify(this.shown)) } catch {}
    this.update()
  }

  toggleMenu() {
    this.menuTarget.hidden = !this.menuTarget.hidden
    this.menuButtonTarget.setAttribute("aria-expanded", String(!this.menuTarget.hidden))
  }

  update() {
    const rows = [...this.element.querySelectorAll("tr.is-selected-row[data-amount]")]
    const amounts = rows.map((r) => Number(r.dataset.amount) || 0)
    const total = this.barTarget.dataset.total
    const all = this.barTarget.dataset.all
    const filtered = total !== all
    this.countTarget.textContent = rows.length ? `選択 ${rows.length} / ${total}` : (filtered ? `${total} / ${all}` : total)
    const sum = amounts.reduce((a, b) => a + b, 0)
    this.sumTarget.textContent = yen(sum)
    this.statsTarget.textContent = amounts.length ? `${yen(sum / amounts.length)} / ${yen(Math.max(...amounts))} / ${yen(Math.min(...amounts))}` : ""
    this.barTarget.querySelectorAll("[data-stat]").forEach((el) => {
      const name = el.dataset.stat
      const needsSelection = name === "sum" || name === "stats"
      el.hidden = !this.shown.includes(name) || (needsSelection && rows.length === 0)
    })
  }
}
