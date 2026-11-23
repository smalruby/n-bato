import { Controller } from "@hotwired/stimulus"

// 表の行を直す(デザインシステム「表の行を直す」、見直し第18回)。
// 行の右の端のボタンで、その行のすぐ下の入力欄を開く。一度に開けるのは 1 件だけ。
// URL の #dest-N(足した・確かめたあとの戻り先)の行は、はじめから開く。
export default class extends Controller {
  static targets = [ "button" ]

  connect() {
    this.reopen = () => this.restore()
    document.addEventListener("turbo:morph", this.reopen)
    this.restore()
  }

  disconnect() { document.removeEventListener("turbo:morph", this.reopen) }

  // はじめは URL の #dest-N の行を開く。読み直し(morph)のあとは、開いていた行を開き直す。
  restore() {
    const id = this.openId || (location.hash && location.hash.slice(1))
    const row = id && document.getElementById(id)
    const button = row && row.querySelector("[data-row-detail-target=button]")
    if (button) this.show(button)
  }

  toggle(event) {
    const button = event.currentTarget
    if (button.getAttribute("aria-expanded") === "true") { this.set(button, false); this.openId = null } else this.show(button)
  }

  show(button) {
    this.buttonTargets.forEach(b => this.set(b, b === button))
    this.openId = button.closest("tr").id
  }

  set(button, open) {
    const detail = document.getElementById(button.getAttribute("aria-controls"))
    if (!detail) return
    detail.hidden = !open
    detail.classList.toggle("is-open", open)
    button.closest("tr").classList.toggle("is-open", open)
    button.setAttribute("aria-expanded", open)
    button.textContent = open ? button.dataset.openLabel : button.dataset.closedLabel
  }
}
