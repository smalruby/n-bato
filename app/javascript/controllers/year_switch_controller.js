import { Controller } from "@hotwired/stimulus"

// 「他の年度に切り替える ▾」の一覧。外を押すか Esc で閉じる。
export default class extends Controller {
  connect() {
    this.onDoc = (e) => { if (!this.element.contains(e.target)) this.element.open = false }
    this.onKey = (e) => { if (e.key === "Escape") this.element.open = false }
    document.addEventListener("click", this.onDoc)
    document.addEventListener("keydown", this.onKey)
  }
  disconnect() {
    document.removeEventListener("click", this.onDoc)
    document.removeEventListener("keydown", this.onKey)
  }
}
