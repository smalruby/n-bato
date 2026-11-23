import { Controller } from "@hotwired/stimulus"

// 文をコピーする(登記すべき事項など)。data-copy-target-value に、コピーする要素の id を書く。
export default class extends Controller {
  static values = { target: String }

  async copy() {
    const el = document.getElementById(this.targetValue)
    if (!el) return
    const label = this.element.textContent
    try {
      await navigator.clipboard.writeText(el.textContent)
      this.element.textContent = "コピーしました"
    } catch (_) {
      const range = document.createRange()
      range.selectNodeContents(el)
      const sel = window.getSelection()
      sel.removeAllRanges()
      sel.addRange(range)
      this.element.textContent = "選びました(⌘C でコピー)"
    }
    setTimeout(() => { this.element.textContent = label }, 2000)
  }
}
