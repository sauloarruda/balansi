import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submit"]

  disable() {
    this.submitTargets.forEach((button) => {
      button.disabled = true
      button.classList.remove("cursor-pointer")
      button.classList.add("cursor-not-allowed", "opacity-50")
    })
  }
}
