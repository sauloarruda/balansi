import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "counter"]

  connect() {
    this.updateCounter()

    if (this.hasInputTarget) {
      this.updateCounterHandler = this.updateCounterHandler || this.updateCounter.bind(this)
      this.inputTarget.addEventListener("input", this.updateCounterHandler)
    }
  }

  disconnect() {
    if (this.hasInputTarget && this.updateCounterHandler) {
      this.inputTarget.removeEventListener("input", this.updateCounterHandler)
    }
  }

  updateCounter() {
    if (this.hasInputTarget && this.hasCounterTarget) {
      const length = this.inputLength()
      const maxLength = this.maxLength()
      const counterSpan = this.counterTarget.querySelector("span")

      if (counterSpan) {
        counterSpan.textContent = length
      }

      // Add visual feedback when approaching limit
      if (length > maxLength * 0.9) {
        this.counterTarget.classList.add("warning")
      } else {
        this.counterTarget.classList.remove("warning")
      }
    }
  }

  inputLength() {
    if (typeof this.inputTarget.value === "string") {
      return this.inputTarget.value.length
    }

    return this.inputTarget.textContent.length
  }

  maxLength() {
    const maxLength = Number(this.inputTarget.maxLength || this.inputTarget.dataset.maxLength)

    return Number.isFinite(maxLength) && maxLength > 0 ? maxLength : 140
  }
}
