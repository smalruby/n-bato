import { Controller } from "@hotwired/stimulus"

// 待つ表示(デザインシステム「待つ表示」)。残りの秒数を出し、0 になったら読み込み直す。
// 読み込み直した画面でもまだ待っていれば、またくり返す(結果が出るまで)。
// 何回目かは URL の ?wait= で数え、上限を超えたら止めて「時間がかかっています」を出す。
//
// 同じ画面の読み直しは Turbo の morph(差分の反映)になり、この要素は残ったまま
// connect() が呼ばれない。そのため turbo:morph のたびに数え直しを始め直す。
// 結果が出て要素が消えれば disconnect() で止まる。
export default class extends Controller {
  static targets = [ "count", "running", "stopped" ]
  static values = { seconds: { type: Number, default: 15 }, maxTries: { type: Number, default: 20 } }

  connect() {
    this.restart = () => this.start()
    document.addEventListener("turbo:morph", this.restart)
    this.start()
  }

  disconnect() {
    clearInterval(this.timer)
    document.removeEventListener("turbo:morph", this.restart)
  }

  start() {
    clearInterval(this.timer)
    this.tries = Number(new URL(location.href).searchParams.get("wait") || 0)
    if (this.tries >= this.maxTriesValue) return this.stop()
    this.left = this.secondsValue
    this.render()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  tick() {
    this.left -= 1
    if (this.left <= 0) return this.now()
    this.render()
  }

  now() {
    clearInterval(this.timer)
    const url = new URL(location.href)
    url.searchParams.set("wait", this.tries + 1)
    window.Turbo ? Turbo.visit(url.toString(), { action: "replace" }) : location.replace(url.toString())
  }

  stop() {
    clearInterval(this.timer)
    if (this.hasRunningTarget) this.runningTarget.hidden = true
    if (this.hasStoppedTarget) this.stoppedTarget.hidden = false
  }

  render() { if (this.hasCountTarget) this.countTarget.textContent = this.left }
}
