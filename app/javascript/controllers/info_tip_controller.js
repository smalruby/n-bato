import { Controller } from "@hotwired/stimulus"

// いまは使えない操作の理由(デザインシステム DisabledAction、見直し第22回。Excel の ScreenTip に当たる)。
// カーソルを当てる・(i) を押す(スマホも)・キーボードで移る、のどれでも説明を出す。
// Esc・外を押す・(i) をもう一度押す・フォーカスが外へ出る、で閉じる。説明は画面の端からはみ出さない位置に置く。
export default class extends Controller {
  static targets = ["trigger", "tip"]

  connect() {
    this.outside = (event) => { if (!this.element.contains(event.target)) this.close() }
    this.reposition = () => this.place()
    this.beforeCache = () => this.close()
    document.addEventListener("turbo:before-cache", this.beforeCache)
  }

  disconnect() {
    this.close()
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  enter() {
    clearTimeout(this.timer)
    this.open()
  }

  leave() {
    if (this.pinned || this.element.contains(document.activeElement)) return
    this.timer = setTimeout(() => this.close(), 200)
  }

  focus() {
    if (this.quiet) return
    clearTimeout(this.timer)
    this.open()
  }

  blur(event) {
    if (!this.element.contains(event.relatedTarget)) this.close()
  }

  // (i) か灰色のボタンを押した: 出したままにする / 閉じる
  toggle(event) {
    event.preventDefault()
    if (this.pinned) return this.close()
    this.pinned = true
    this.open()
  }

  escape() {
    if (!this.isOpen) return
    this.close()
    this.quiet = true
    this.triggerTarget.focus()
    this.quiet = false
  }

  open() {
    if (this.isOpen) return
    this.isOpen = true
    this.tipTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.place()
    document.addEventListener("click", this.outside, true)
    window.addEventListener("scroll", this.reposition, true)
    window.addEventListener("resize", this.reposition)
  }

  close() {
    clearTimeout(this.timer)
    this.pinned = false
    if (!this.isOpen) return
    this.isOpen = false
    this.tipTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.outside, true)
    window.removeEventListener("scroll", this.reposition, true)
    window.removeEventListener("resize", this.reposition)
  }

  // 組の右端にそろえて下に出す。はみ出すなら左へずらし、下に入らなければ上に出す。
  place() {
    const tip = this.tipTarget
    const box = this.element.getBoundingClientRect()
    const edge = 12, gap = 4
    const width = tip.offsetWidth, height = tip.offsetHeight
    const left = Math.max(edge, Math.min(box.right - width, window.innerWidth - width - edge))
    let top = box.bottom + gap
    if (top + height > window.innerHeight - edge && box.top - gap - height >= edge) top = box.top - gap - height
    tip.style.left = `${left}px`
    tip.style.top = `${top}px`
  }
}
