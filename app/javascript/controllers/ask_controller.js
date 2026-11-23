import { Controller } from "@hotwired/stimulus"

// 右ペイン「AI に聞く」(デザインシステム AskAI)。答えと、やる操作の案を出す。操作は「実行」を押してから行う。
export default class extends Controller {
  static targets = ["q", "image", "send", "answer"]
  static values = { url: String, performUrl: String, screen: String }

  get csrf() { return document.querySelector("meta[name=csrf-token]")?.content }

  async send(event) {
    event.preventDefault()
    const body = new FormData()
    body.append("q", this.qTarget.value)
    body.append("screen", this.screenValue)
    if (this.imageTarget.files[0]) body.append("image", this.imageTarget.files[0])
    this.sendTarget.disabled = true
    this.show("考えています…")
    let data
    try {
      const res = await fetch(this.urlValue, { method: "POST", body, headers: { "Accept": "application/json", "X-CSRF-Token": this.csrf } })
      data = await res.json()
    } catch {
      data = { answer: "通信が切れました。もう一度押してください。" }
    }
    this.sendTarget.disabled = false
    this.show(data.answer, data.action)
  }

  show(text, action) {
    const box = this.answerTarget
    box.hidden = false
    box.replaceChildren()
    const p = document.createElement("p")
    p.textContent = text
    box.append(p)
    if (!action) return
    const card = document.createElement("div")
    card.className = "nb-ask-action"
    const label = document.createElement("p")
    label.textContent = `やる操作の案: ${action.label}`
    card.append(label)
    let reason = null
    if (action.reason_required) {
      reason = document.createElement("input")
      reason.className = "nb-input"
      reason.placeholder = "締めた年度を直す理由"
      reason.setAttribute("aria-label", "締めた年度を直す理由")
      card.append(reason)
    }
    const run = document.createElement("button")
    run.type = "button"
    run.className = "nb-btn nb-btn--primary"
    run.textContent = "実行"
    run.addEventListener("click", () => this.perform(action.token, reason?.value, run))
    card.append(run)
    box.append(card)
  }

  async perform(token, reason, button) {
    button.disabled = true
    const body = new FormData()
    body.append("token", token)
    if (reason) body.append("reason", reason)
    body.append("undo_scope", document.querySelector("[data-undo-scope-value]")?.dataset.undoScopeValue || "")
    const res = await fetch(this.performUrlValue, { method: "POST", body, headers: { "Accept": "application/json", "X-CSRF-Token": this.csrf } })
    const data = await res.json().catch(() => ({ ok: false, message: "通信が切れました" }))
    this.show(data.message)
    if (data.ok && data.location) window.Turbo.visit(data.location)
    else if (!data.ok) button.disabled = false
  }
}
