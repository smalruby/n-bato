import { Controller } from "@hotwired/stimulus"

// 絞り込み(デザインシステム FilterBar)。欄を変えたら、すぐ絞り込む。
export default class extends Controller {
  submit() { this.element.requestSubmit() }
}
