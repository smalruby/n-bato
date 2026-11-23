import { Controller } from "@hotwired/stimulus"

// 「この画面の使い方」を畳む・開く。人ごと・画面ごとにサーバーに覚える(デザインシステム HelpPanel)。
export default class extends Controller {
  static targets = ["body", "button"]
  static values = { screen: String, collapsed: Boolean }

  toggle() {
    this.collapsedValue = !this.collapsedValue
    this.bodyTarget.hidden = this.collapsedValue
    this.buttonTarget.textContent = this.collapsedValue ? "開く" : "畳む"
    this.buttonTarget.setAttribute("aria-expanded", String(!this.collapsedValue))
    const body = new FormData()
    body.append("screen", this.screenValue)
    body.append("collapsed", this.collapsedValue ? "1" : "0")
    fetch("/ui_prefs/help", { method: "POST", body, headers: { "Accept": "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content } })
  }
}
