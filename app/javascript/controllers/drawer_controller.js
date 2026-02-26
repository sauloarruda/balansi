import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer", "backdrop"]

  connect() {
    this.isOpen = false
    this.handleEscape = this.handleEscape.bind(this)
  }

  toggle(event) {
    event?.preventDefault()
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.drawerTarget.classList.remove("-translate-x-full")
    this.drawerTarget.classList.add("translate-x-0")
    this.drawerTarget.setAttribute("aria-hidden", "false")
    this.backdropTarget.classList.remove("hidden")
    this.backdropTarget.classList.add("block")
    document.body.classList.add("overflow-hidden")
    document.addEventListener("keydown", this.handleEscape)
    this.isOpen = true
  }

  close(event) {
    event?.preventDefault()
    this.drawerTarget.classList.add("-translate-x-full")
    this.drawerTarget.classList.remove("translate-x-0")
    this.drawerTarget.setAttribute("aria-hidden", "true")
    this.backdropTarget.classList.add("hidden")
    this.backdropTarget.classList.remove("block")
    document.body.classList.remove("overflow-hidden")
    document.removeEventListener("keydown", this.handleEscape)
    this.isOpen = false
  }

  handleEscape(event) {
    if (event.key === "Escape") {
      this.close(event)
    }
  }
}
