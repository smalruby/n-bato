import { Controller } from "@hotwired/stimulus"

// 上部バーの保存状態(SaveStatus)と、元に戻す・やり直す(UndoBar)。⌘Z / ⌘⇧Z / Ctrl+Y でも動く。
// 自動保存(autosave_controller)は、保存の始まりと終わりを "nb:saving" / "nb:saved" / "nb:save-error" で知らせる。
export default class extends Controller {
  static targets = ["status", "undoButton", "redoButton", "undoCount", "redoCount", "undoItem", "redoItem", "history"]
  static values = { url: String, scope: String }

  connect() {
    this.onKey = this.onKey.bind(this)
    document.addEventListener("keydown", this.onKey)
    this.element.addEventListener("nb:saving", () => this.show("saving", "保存中…"))
    this.element.addEventListener("nb:saved", (e) => this.saved(e.detail))
    this.element.addEventListener("nb:save-error", (e) => this.show("error", e.detail.message))
    // 保存のあと画面を読み直しても(morph)、「保存しました」を出したままにする
    this.restore = () => { if (window.nbLastStatus) this.show(...window.nbLastStatus); this.flash() }
    document.addEventListener("turbo:render", this.restore)
    document.addEventListener("turbo:load", this.restore)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
    document.removeEventListener("turbo:render", this.restore)
    document.removeEventListener("turbo:load", this.restore)
  }

  // 戻した(移った)記録を光らせる。window.nbHighlight = { record: "journal_entry_12", field: "amount", moved: true }
  flash() {
    const h = window.nbHighlight
    if (!h) return
    const row = document.getElementById(h.record)
    if (!row) return
    window.nbHighlight = null
    const input = h.field && row.querySelector(`[name$="[${h.field}]"]`)
    const cells = input ? [input.closest("td")] : Array.from(row.children)
    const cls = h.moved ? "is-moved" : "is-flash"
    cells.forEach((c) => { c.classList.add(cls); setTimeout(() => c.classList.remove(cls), 2000) })
    row.scrollIntoView({ block: "nearest" })
  }

  show(state, text) {
    if (!this.hasStatusTarget) return
    this.statusTarget.className = `nb-save nb-save--${state}`
    this.statusTarget.textContent = text
    if (state === "saved" || state === "error") window.nbLastStatus = [state, text]
  }

  saved(detail = {}) {
    this.show("saved", `保存しました ${detail.saved_at || ""}`.trim())
    this.setCounts(detail)
    if (this.hasHistoryTarget) this.historyTarget.reload()
  }

  setCounts({ undo, redo, undo_peek, redo_peek }) {
    if (undo === undefined) return
    this.setPeek("undo", "元に戻す", "⌘Z / Ctrl+Z", undo_peek)
    this.setPeek("redo", "やり直す", "⌘⇧Z / Ctrl+Y", redo_peek)
    if (this.hasUndoCountTarget) { this.undoCountTarget.textContent = undo; this.undoButtonTarget.disabled = undo === 0 }
    if (this.hasRedoCountTarget) { this.redoCountTarget.textContent = redo; this.redoButtonTarget.disabled = redo === 0 }
  }

  setPeek(kind, name, keys, peek) {
    const cap = kind[0].toUpperCase() + kind.slice(1)
    if (!this[`has${cap}ItemTarget`] || !this[`has${cap}ButtonTarget`]) return
    const item = this[`${kind}ItemTarget`], button = this[`${kind}ButtonTarget`]
    item.textContent = peek ? `: ${peek.item}` : ""
    button.title = `${peek?.detail || name}(${keys})`
  }

  // 行き先がいまの画面(パスと指定された条件が同じ)なら true
  sameScreen(location) {
    if (!location) return true
    const to = new URL(location, window.location.origin), here = new URL(window.location.href)
    if (to.pathname !== here.pathname) return false
    for (const [k, v] of to.searchParams) if (here.searchParams.get(k) !== v) return false
    return true
  }

  undo() { this.send("/undo") }
  redo() { this.send("/redo") }

  async send(path) {
    if (!this.scopeValue) return
    this.show("saving", "保存中…")
    const res = await fetch(path, {
      method: "POST",
      headers: { "Accept": "application/json", "Content-Type": "application/json", "X-CSRF-Token": this.csrf },
      body: JSON.stringify({ scope: this.scopeValue })
    })
    const data = await res.json().catch(() => ({ ok: false, message: "通信が切れました。もう一度押してください" }))
    if (!data.ok) { this.show("error", data.message); return }
    // 戻した記録のある画面へ移る(同じ画面なら読み直す。Turbo の morph でスクロールと選択位置を保つ)
    window.nbHighlight = data.highlight || null
    const to = this.sameScreen(data.location) ? window.location.href : data.location
    window.Turbo.visit(to, { action: to === window.location.href ? "replace" : "advance" })
    document.addEventListener("turbo:load", () => this.show("saved", data.message), { once: true })
  }

  onKey(e) {
    if (!this.scopeValue || !(e.metaKey || e.ctrlKey)) return
    const key = e.key.toLowerCase()
    const isRedo = (key === "z" && e.shiftKey) || key === "y"
    if (key !== "z" && key !== "y") return
    // 入力中(まだ確定していない文字がある)は、ブラウザの元に戻すに任せる
    const el = document.activeElement
    if (el && el.matches("input, textarea") && el.dataset.original !== undefined && el.value !== el.dataset.original) return
    e.preventDefault()
    isRedo ? this.redo() : this.undo()
  }

  get csrf() { return document.querySelector("meta[name=csrf-token]")?.content }
}
