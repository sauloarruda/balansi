import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    pattern: String,
    lazy: { type: Boolean, default: false },
    placeholderChar: { type: String, default: "_" }
  }

  connect() {
    if (!this.hasPatternValue) return
    if (typeof IMask === "undefined") return

    this.mask = IMask(this.element, {
      mask: this.patternValue,
      lazy: this.lazyValue,
      placeholderChar: this.placeholderCharValue,
      overwrite: true
    })
  }

  disconnect() {
    if (this.mask && typeof this.mask.destroy === "function") {
      this.mask.destroy()
    }
  }
}
