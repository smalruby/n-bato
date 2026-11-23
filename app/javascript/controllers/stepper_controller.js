import { Controller } from "@hotwired/stimulus"

// 手順の一覧(Stepper)。クリックか Enter で手順を開く。↑↓ で手順を移る。
export default class extends Controller {
  go(event) {
    if (event.target.closest("a")) return
    window.Turbo.visit(event.currentTarget.dataset.href)
  }

  key(event) {
    const li = event.currentTarget
    if (event.key === "Enter") { window.Turbo.visit(li.dataset.href); return }
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return
    event.preventDefault()
    const items = Array.from(this.element.querySelectorAll(".nb-step"))
    const next = items[items.indexOf(li) + (event.key === "ArrowDown" ? 1 : -1)]
    if (next) next.focus()
  }
}
