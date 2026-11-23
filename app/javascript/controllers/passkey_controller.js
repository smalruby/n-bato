import { Controller } from "@hotwired/stimulus"

// パスキー(WebAuthn、デザインシステム SignIn / PasskeyList、見直し第14回)。
// ブラウザに備わっている navigator.credentials を直接使う(JavaScript のライブラリは足さない)。
// 実機(Touch ID・スマホなど)が要るので、ここは自動テストの対象外(:nocov: と同じ扱い)。人と一緒に確かめる。
//
//   data-passkey-options-url-value  … 申し込み(チャレンジ)を取る先
//   data-passkey-url-value          … 結果を送る先
//   data-passkey-mode-value         … "get"(ログイン・確かめ直し) か "create"(足す)
//   data-passkey-conditional-value  … true なら、メールアドレスの欄でもパスキーの候補を出す(ログインの画面)
export default class extends Controller {
  static targets = ["button", "name", "error", "unsupported"]
  static values = { optionsUrl: String, url: String, mode: String, conditional: Boolean }

  connect() {
    if (!window.PublicKeyCredential || !navigator.credentials) {
      this.buttonTargets.forEach((b) => (b.hidden = true))
      if (this.hasUnsupportedTarget) this.unsupportedTarget.hidden = false
      return
    }
    if (this.conditionalValue) this.startConditional()
  }

  disconnect() { this.abort?.abort() }

  async start(event) {
    event?.preventDefault()
    this.abort?.abort()
    await this.run(false)
  }

  async startConditional() {
    if (!PublicKeyCredential.isConditionalMediationAvailable) return
    try {
      if (!(await PublicKeyCredential.isConditionalMediationAvailable())) return
    } catch { return }
    await this.run(true)
  }

  async run(conditional) {
    this.showError("")
    const button = this.hasButtonTarget ? this.buttonTarget : null
    if (!conditional && button) button.disabled = true
    try {
      const options = await this.post(this.optionsUrlValue, {})
      if (options.ok === false) throw new Error(options.message)
      let credential
      if (this.modeValue === "create") {
        credential = await navigator.credentials.create({ publicKey: this.creationOptions(options) })
      } else {
        this.abort = new AbortController()
        credential = await navigator.credentials.get({
          publicKey: this.requestOptions(options),
          mediation: conditional ? "conditional" : "optional",
          signal: this.abort.signal
        })
      }
      if (!credential) return
      const body = { credential: this.toJSON(credential) }
      if (this.hasNameTarget) body.name = this.nameTarget.value
      const result = await this.post(this.urlValue, body)
      if (result.ok && result.redirect) { window.location.href = result.redirect; return }
      this.showError(result.message || "うまくいきませんでした。もう一度試してください")
    } catch (e) {
      if (e?.name === "AbortError") return
      if (e?.name === "NotAllowedError") {
        if (!conditional) this.showError("パスキーを使うのを取りやめたか、時間が切れました。もう一度押してください")
        return
      }
      if (!conditional) this.showError(e?.message || "うまくいきませんでした。もう一度試してください")
    } finally {
      if (!conditional && button) button.disabled = false
    }
  }

  creationOptions(o) {
    return {
      ...o,
      challenge: this.fromB64(o.challenge),
      user: { ...o.user, id: this.fromB64(o.user.id) },
      excludeCredentials: (o.excludeCredentials || []).map((c) => ({ ...c, id: this.fromB64(c.id) }))
    }
  }

  requestOptions(o) {
    return {
      ...o,
      challenge: this.fromB64(o.challenge),
      allowCredentials: (o.allowCredentials || []).map((c) => ({ ...c, id: this.fromB64(c.id) }))
    }
  }

  toJSON(c) {
    if (typeof c.toJSON === "function") return c.toJSON()
    const r = c.response
    const response = { clientDataJSON: this.toB64(r.clientDataJSON) }
    if (r.attestationObject) {
      response.attestationObject = this.toB64(r.attestationObject)
      if (r.getTransports) response.transports = r.getTransports()
    } else {
      response.authenticatorData = this.toB64(r.authenticatorData)
      response.signature = this.toB64(r.signature)
      if (r.userHandle) response.userHandle = this.toB64(r.userHandle)
    }
    return { id: c.id, rawId: this.toB64(c.rawId), type: c.type, response,
             authenticatorAttachment: c.authenticatorAttachment, clientExtensionResults: c.getClientExtensionResults?.() || {} }
  }

  // base64url と ArrayBuffer の変換(小さいので自前で書く)
  fromB64(s) {
    const b = atob(s.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(s.length / 4) * 4, "="))
    return Uint8Array.from(b, (ch) => ch.charCodeAt(0)).buffer
  }

  toB64(buf) {
    let s = ""
    new Uint8Array(buf).forEach((x) => (s += String.fromCharCode(x)))
    return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
  }

  async post(url, body) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": token },
      body: JSON.stringify(body)
    })
    return res.json()
  }

  showError(text) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = text
    this.errorTarget.hidden = !text
  }
}
