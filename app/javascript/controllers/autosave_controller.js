import { Controller } from "@hotwired/stimulus"
import { askYear, askAlso } from "lib/year_guard"

// 入力したらすぐ保存する(保存ボタンを置かない)。
// <form data-controller="autosave" action=… method=patch> の中の入力欄が確定したとき(change)に、その 1 項目だけを送る。
// 送り先は JSON で { ok, saved_at, undo, redo } か { ok: false, message, errors } を返す。
// 送る順は守る(前の保存が終わってから次を送る)。
export default class extends Controller {
  static values = { scope: String, refresh: Boolean, year: Number }

  connect() {
    this.queue = Promise.resolve()
    this.element.querySelectorAll("input, select, textarea").forEach((el) => this.remember(el))
    // 自分が form のときだけ送信を止める(中にある削除ボタンの form は止めない)
    this.element.addEventListener("submit", (e) => { if (e.target === this.element) e.preventDefault() })
  }

  remember(el) { if (el.type !== "checkbox") el.dataset.original = el.value }

  // input: 入力中の印(dirty)
  mark(event) {
    const el = event.target
    const cell = el.closest("td, .nb-field-value") || el
    cell.classList.toggle("is-dirty", el.value !== el.dataset.original)
  }

  // Esc: 入力をやめて元の値に戻す
  cancel(event) {
    if (event.key !== "Escape") return
    const el = event.target
    if (el.dataset.original === undefined) return
    el.value = el.dataset.original
    this.mark(event)
  }

  save(event) {
    const el = event.target
    if (!el.name || el.closest("tr.is-new")) return   // 新しい行は new-row がまとめて保存する
    if (el.type !== "checkbox" && el.value === el.dataset.original) return
    // Enter とフォーカスが外れたときの両方で change が来ても、同じ値は 1 回だけ送る
    if (el.type !== "checkbox" && el.dataset.pending === el.value) return
    el.dataset.pending = el.value
    const form = el.form || this.element
    const body = new FormData()
    body.append("_method", "patch")
    body.append("undo_scope", this.scopeValue)
    if (this.hasYearValue) body.append("sheet_year", this.yearValue)
    if (el.type === "checkbox") {
      body.append(el.name, el.checked ? (el.value || "1") : "0")
    } else {
      body.append(el.name, el.value)
    }
    const url = el.dataset.url || form.action
    const cell = el.closest("td, .nb-field-value, li") || el
    this.queue = this.queue.then(() => this.send(url, body, el, cell))
  }

  async send(url, body, el, cell) {
    cell.classList.remove("is-dirty", "is-error", "is-saved")
    cell.classList.add("is-saving")
    this.dispatch("saving", { prefix: "nb", bubbles: true })
    let data, status
    try {
      const res = await fetch(url, { method: "POST", body, headers: { "Accept": "application/json", "X-CSRF-Token": this.csrf } })
      status = res.status
      data = await res.json()
    } catch {
      data = { ok: false, message: "保存できませんでした(通信が切れました)。もう一度入力してください" }
    }
    cell.classList.remove("is-saving")
    delete el.dataset.pending
    if (data.ok) {
      if (el.type !== "checkbox") el.dataset.original = el.value
      if (data.value !== undefined && el.type !== "checkbox") { el.value = data.value; el.dataset.original = data.value }
      // 保存したセルを 2 秒だけ緑にする(目はセルを見ているので、上部バーだけでは気づかない)
      cell.classList.add("is-saved")
      setTimeout(() => cell.classList.remove("is-saved"), 2000)
      this.dispatch("saved", { prefix: "nb", detail: data, bubbles: true })
      // 並びが変わる項目(data-reorder)は、すぐ正しい位置へ移し、移った行に色を付ける
      const row = el.closest("tr[id]")
      if (el.dataset.reorder !== undefined && row && !data.location) {
        window.nbHighlight = { record: row.id, moved: true }
        window.Turbo.visit(window.location.href, { action: "replace" })
      } else if (this.refreshValue) {
        // 状態がほかの場所(手順の一覧など)に出る画面は、保存のたびに読み直す(morph)
        window.Turbo.visit(window.location.href, { action: "replace" })
      }
      if (data.also) askAlso(cell, data.also, this.csrf)
      if (data.location) {
        // 別の年度へ移した: その年度の表へ移り、移した行を光らせる
        window.nbHighlight = { record: data.record, moved: true }
        window.Turbo.visit(data.location)
      }
    } else if (status === 409 && (data.code === "outside_year" || data.code === "reason_required")) {
      // デザインシステム「年度」: 年度の外の日付・締めた年度は、聞いてから保存する
      cell.classList.add("is-dirty")
      askYear(cell, data, {
        resend: (extra) => {
          Object.entries(extra).forEach(([k, v]) => body.set(k, v))
          el.dataset.pending = el.value
          this.queue = this.queue.then(() => this.send(url, body, el, cell))
        },
        cancel: () => { if (el.dataset.original !== undefined) el.value = el.dataset.original; cell.classList.remove("is-dirty"); el.focus() }
      })
    } else {
      cell.classList.add("is-error")
      cell.title = data.message
      this.dispatch("save-error", { prefix: "nb", detail: data, bubbles: true })
    }
  }

  get csrf() { return document.querySelector("meta[name=csrf-token]")?.content }
}
