// 「開く」で来たやることがあるとき、締めた年度の理由の欄に最初から入れておく(デザインシステム「やること」)。
// body の data-reason-default に文があれば、空の理由の欄(name="reason")に入れる。締めを解く理由には入れない。
export function reasonDefault() { return document.body?.dataset.reasonDefault || "" }

function fill() {
  const text = reasonDefault()
  if (!text) return
  document.querySelectorAll('input[name="reason"]').forEach((el) => {
    if (!el.value && !el.closest("[data-no-reason-default]")) el.value = text
  })
}
document.addEventListener("turbo:load", fill)
