import { reasonDefault } from "lib/reason_default"
// デザインシステム「年度」の確かめ。保存の返事が 409(code: outside_year / reason_required)のとき、
// セルの下に枠を出して、移すか・理由を書くかを聞く。決めたら resend(extra) を呼ぶ。やめたら cancel() を呼ぶ。
// 締めた年度にかかるときは、理由を書いて、もう一度押して決める(2 回押し)。
export function askYear(cell, data, { resend, cancel }) {
  document.querySelectorAll(".nb-pop.is-year").forEach((p) => p.remove())
  const pop = document.createElement("div")
  pop.className = "nb-pop is-year"
  pop.setAttribute("role", "alertdialog")
  const p = (text, bold) => { const el = document.createElement("p"); el.style.margin = "0 0 6px"; if (bold) { const b = document.createElement("b"); b.textContent = text; el.append(b) } else el.textContent = text; return el }
  pop.append(p(data.message, true))
  const states = Object.values(data.states || {})
  if (data.code === "outside_year" && states.length) {
    pop.append(p(states.map((s) => `${s.label}: ${s.state_label}`).join(" / ")))
    if (data.reason_required) pop.append(p("締めた年度にかかるので、両方の年度の書類が変わり、提出済みなら再提出が要ります。"))
  }
  let reason = null
  const needsReason = data.code === "reason_required" || data.reason_required
  if (needsReason) {
    const label = document.createElement("label")
    label.textContent = "直す理由 "
    reason = document.createElement("input")
    reason.type = "text"
    reason.className = "nb-input"
    reason.style.width = "100%"
    reason.setAttribute("aria-label", "直す理由")
    reason.value = reasonDefault()
    label.append(reason)
    pop.append(label)
  }
  const row = document.createElement("div")
  row.style.cssText = "display:flex;gap:6px;flex-wrap:wrap;margin-top:6px"
  const ok = document.createElement("button")
  ok.type = "button"
  ok.className = "nb-btn nb-btn--primary"
  const target = data.code === "outside_year" ? data.states?.[data.to]?.label : null
  const okLabel = target ? `${target}へ移す` : "理由を残して直す"
  ok.textContent = okLabel
  const no = document.createElement("button")
  no.type = "button"
  no.className = "nb-btn"
  no.textContent = data.code === "outside_year" ? "日付を直す" : "やめる(Esc)"
  row.append(ok, no)
  pop.append(row)

  let armed = !needsReason
  ok.addEventListener("click", () => {
    if (reason && !reason.value.trim()) { reason.focus(); reason.classList.add("nb-input--error"); return }
    if (!armed) { armed = true; ok.textContent = `${okLabel}(もう一度押す)`; ok.classList.add("nb-btn--armed"); setTimeout(() => { armed = false; ok.textContent = okLabel; ok.classList.remove("nb-btn--armed") }, 4000); return }
    pop.remove()
    resend({ move: data.code === "outside_year" ? "1" : "", reason: reason ? reason.value.trim() : "" })
  })
  const close = () => { pop.remove(); cancel() }
  no.addEventListener("click", close)
  pop.addEventListener("keydown", (e) => { if (e.key === "Escape") close() })

  const r = cell.getBoundingClientRect()
  pop.style.left = `${Math.max(8, Math.min(r.left, window.innerWidth - 380))}px`
  pop.style.top = `${Math.min(r.bottom + 2, window.innerHeight - 200)}px`
  document.body.append(pop)
  ;(reason || ok).focus()
}

// ほかの年度にも同じ変更を効かせるかを聞く(デザインシステム「年度」: ほかの年度にも同じ値があるとき)。
// data.also = { message, years, labels, field, url }
export function askAlso(cell, also, csrf) {
  document.querySelectorAll(".nb-pop.is-year").forEach((p) => p.remove())
  const pop = document.createElement("div")
  pop.className = "nb-pop is-year"
  pop.setAttribute("role", "dialog")
  const msg = document.createElement("p")
  msg.style.margin = "0 0 6px"
  msg.textContent = also.message
  const row = document.createElement("div")
  row.style.cssText = "display:flex;gap:6px;flex-wrap:wrap"
  const yes = document.createElement("button")
  yes.type = "button"
  yes.className = "nb-btn nb-btn--primary"
  yes.textContent = `${also.labels.join("・")}も直す`
  const no = document.createElement("button")
  no.type = "button"
  no.className = "nb-btn"
  no.textContent = "この年度だけ"
  row.append(yes, no)
  pop.append(msg, row)
  yes.addEventListener("click", async () => {
    const body = new FormData()
    body.append("field", also.field)
    also.years.forEach((y) => body.append("years[]", y))
    pop.remove()
    await fetch(also.url, { method: "POST", body, headers: { "Accept": "application/json", "X-CSRF-Token": csrf } })
    window.Turbo.visit(window.location.href, { action: "replace" })
  })
  no.addEventListener("click", () => pop.remove())
  const r = cell.getBoundingClientRect()
  pop.style.left = `${Math.max(8, Math.min(r.left, window.innerWidth - 380))}px`
  pop.style.top = `${Math.min(r.bottom + 2, window.innerHeight - 160)}px`
  document.body.append(pop)
  yes.focus()
}
