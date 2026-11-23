import { Controller } from "@hotwired/stimulus"

// 元に戻せない操作は、ダイアログを出さず 2 回押しで実行する(デザインシステムの原則 5)。
// 1 回目で「もう一度押すと〜」に変わり、4 秒たつと元に戻る。
export default class extends Controller {
  static targets = ["button"]

  check(event) {
    if (this.armed) return
    event.preventDefault()
    this.armed = true
    const b = this.buttonTarget
    this.label = b.value || b.textContent
    this.setLabel(b.dataset.armedLabel || "もう一度押すと実行します")
    b.classList.remove("nb-btn--danger")
    b.classList.add("nb-btn--armed")
    this.timer = setTimeout(() => this.disarm(), 4000)
  }

  disarm() {
    this.armed = false
    const b = this.buttonTarget
    this.setLabel(this.label)
    b.classList.add("nb-btn--danger")
    b.classList.remove("nb-btn--armed")
  }

  setLabel(text) {
    const b = this.buttonTarget
    if (b.tagName === "INPUT") b.value = text; else b.textContent = text
  }

  disconnect() { clearTimeout(this.timer) }
}
