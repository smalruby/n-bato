import { Controller } from "@hotwired/stimulus"
import { askYear } from "lib/year_guard"

// 表のいちばん下の空の行(デザインシステム Sheet の「新しい行」)。
// 必須の項目(日付・借方科目・貸方科目・金額)がそろったら、1 件の記録として保存する。そろうまでは黄色(is-dirty)のまま。
const REQUIRED = ["entry_date", "debit_account_id", "credit_account_id", "amount"]

export default class extends Controller {
  static targets = ["status"]
  static values = { url: String }

  field(name) { return this.element.querySelector(`[name="journal_entry[${name}]"]`) }

  check() {
    if (this.sending) return
    const missing = REQUIRED.filter((n) => !this.field(n)?.value)
    if (missing.length) {
      const labels = { entry_date: "日付", debit_account_id: "借方科目", credit_account_id: "貸方科目", amount: "金額" }
      this.statusTarget.textContent = `あと ${missing.map((m) => labels[m]).join("・")}`
      return
    }
    this.save()
  }

  async save(extra = {}) {
    this.sending = true
    this.statusTarget.textContent = "保存中…"
    const body = new FormData()
    this.element.querySelectorAll("input[name^='journal_entry']").forEach((el) => body.append(el.name, el.value))
    const wrap = this.element.closest("[data-autosave-scope-value]")
    body.append("undo_scope", wrap?.dataset.autosaveScopeValue || "journal_entries")
    if (wrap?.dataset.autosaveYearValue) body.append("sheet_year", wrap.dataset.autosaveYearValue)
    Object.entries(extra).forEach(([k, v]) => body.set(k, v))
    let data, status
    try {
      const res = await fetch(this.urlValue, { method: "POST", body, headers: { "Accept": "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content } })
      status = res.status
      data = await res.json()
    } catch {
      data = { ok: false, message: "保存できませんでした(通信が切れました)。もう一度入力してください" }
    }
    this.sending = false
    if (!data.ok && status === 409 && (data.code === "outside_year" || data.code === "reason_required")) {
      this.statusTarget.textContent = "確かめています"
      askYear(this.element.querySelector("td"), data, {
        resend: (more) => this.save(more),
        cancel: () => { this.statusTarget.textContent = "日付を直してください"; this.field("entry_date")?.focus() }
      })
      return
    }
    if (!data.ok) {
      this.statusTarget.textContent = data.message
      this.element.classList.add("is-error")
      this.dispatch("save-error", { prefix: "nb", detail: data, bubbles: true })
      return
    }
    this.dispatch("saved", { prefix: "nb", detail: data, bubbles: true })
    window.nbHighlight = { record: data.record, moved: true }
    // 別の年度の日付なら、その年度の表へ移る
    window.Turbo.visit(data.location || window.location.href, { action: "replace" })
  }
}
