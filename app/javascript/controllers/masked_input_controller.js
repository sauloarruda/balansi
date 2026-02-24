import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    pattern: String,
    lazy: { type: Boolean, default: false },
    placeholderChar: { type: String, default: "_" }
  }

  async connect() {
    if (!this.hasPatternValue) return

    const IMask = await this.loadMaskLibrary()
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

  async loadMaskLibrary() {
    if (!this.constructor.imaskLibraryPromise) {
      this.constructor.imaskLibraryPromise = import("https://cdn.jsdelivr.net/npm/imask@7.6.1/+esm")
        .then((module) => module.default)
    }

    return this.constructor.imaskLibraryPromise
  }
}
