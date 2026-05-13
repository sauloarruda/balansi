import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["manualFields", "manualInput", "toggle"]

  connect() {
    this.update()
  }

  update() {
    const useAi = this.toggleTarget.checked

    this.manualFieldsTarget.hidden = useAi
    this.toggleTarget.setAttribute("aria-expanded", (!useAi).toString())
    this.manualInputTargets.forEach((input) => {
      input.disabled = useAi
    })
  }
}
