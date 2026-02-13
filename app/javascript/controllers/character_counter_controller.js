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
      const length = this.inputTarget.value.length
      const maxLength = this.inputTarget.maxLength || 140
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
}
