import { Controller } from "@hotwired/stimulus"

// 待つ表示(デザインシステム「待つ表示」)。残りの秒数を出し、0 になったら読み込み直す。
// 読み込み直した画面でもまだ待っていれば、この部品がまた始まる(結果が出るまでくり返す)。
// 何回目かは URL の ?wait= で数え、上限を超えたら止めて「時間がかかっています」を出す。
export default class extends Controller {
  static targets = [ "count", "running", "stopped" ]
  static values = { seconds: { type: Number, default: 15 }, maxTries: { type: Number, default: 20 } }

  connect() {
    this.tries = Number(new URL(location.href).searchParams.get("wait") || 0)
    if (this.tries >= this.maxTriesValue) return this.stop()
    this.left = this.secondsValue
    this.render()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() { clearInterval(this.timer) }

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
