import { Controller } from "@hotwired/stimulus"

// シートのキーボード操作: Enter で確定して下のセルへ、Shift+Enter で上へ。
// ↑↓ は select 以外の入力欄で、同じ列の上下のセルへ移る。
export default class extends Controller {
  move(event) {
    const el = event.target
    if (!el.classList.contains("nb-cell-input")) return
    let dir = 0
    if (event.key === "Enter") dir = event.shiftKey ? -1 : 1
    else if (el.tagName !== "SELECT" && event.key === "ArrowDown") dir = 1
    else if (el.tagName !== "SELECT" && event.key === "ArrowUp") dir = -1
    if (!dir) return
    const td = el.closest("td"), tr = td.parentElement
    const col = Array.from(tr.children).indexOf(td)
    let row = dir > 0 ? tr.nextElementSibling : tr.previousElementSibling
    while (row) {
      const next = row.children[col]?.querySelector(".nb-cell-input")
      if (next) {
        event.preventDefault()
        el.dispatchEvent(new Event("change", { bubbles: true }))
        next.focus()
        if (next.select) next.select()
        return
      }
      row = dir > 0 ? row.nextElementSibling : row.previousElementSibling
    }
  }

  // 行を選ぶ(表の下の集計に使う)。クリックで 1 行、Shift で範囲、⌘ / Ctrl で 1 行ずつ足し引き。
  // 変更できない行(data-readonly-reason)を押したら、理由と直し方を出す。
  select(event) {
    const row = event.target.closest("tbody tr")
    if (!row || row.classList.contains("is-new") || row.classList.contains("is-group")) return
    const rows = [...this.element.querySelectorAll("tbody tr:not(.is-new):not(.is-group)")]
    if (event.shiftKey && this.anchor && rows.includes(this.anchor)) {
      const [a, b] = [rows.indexOf(this.anchor), rows.indexOf(row)].sort((x, y) => x - y)
      rows.forEach((r, i) => r.classList.toggle("is-selected-row", i >= a && i <= b))
    } else if (event.metaKey || event.ctrlKey) {
      row.classList.toggle("is-selected-row")
      this.anchor = row
    } else {
      rows.forEach((r) => r.classList.toggle("is-selected-row", r === row))
      this.anchor = row
    }
    this.dispatch("selection", { prefix: "nb", bubbles: true })
    if (row.dataset.readonlyReason && event.target.closest("td.is-readonly") && !event.target.closest("a")) this.explain(event.target.closest("td"), row.dataset.readonlyReason)
  }

  explain(cell, text) {
    document.querySelectorAll(".nb-pop.is-explain").forEach((p) => p.remove())
    const pop = document.createElement("div")
    pop.className = "nb-pop is-explain"
    pop.setAttribute("role", "status")
    pop.textContent = text
    const r = cell.getBoundingClientRect()
    pop.style.left = `${Math.min(r.left, window.innerWidth - 380)}px`
    pop.style.top = `${r.bottom + 2}px`
    document.body.append(pop)
    const remove = () => pop.remove()
    setTimeout(remove, 4000)
    document.addEventListener("turbo:before-render", remove, { once: true })
  }
}
