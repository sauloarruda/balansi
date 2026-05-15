import { Controller } from "@hotwired/stimulus"
import { createPopper } from "@popperjs/core"

export default class extends Controller {
  static targets = ["tip"]

  connect() {
    this.show = this.show.bind(this)
    this.hide = this.hide.bind(this)
    this.toggle = this.toggle.bind(this)
    this.scheduleHide = this.scheduleHide.bind(this)
    this.cancelHide = this.cancelHide.bind(this)
    this.hideOnOutsideClick = this.hideOnOutsideClick.bind(this)
    this.hideOnEscape = this.hideOnEscape.bind(this)

    this.element.addEventListener("mouseenter", this.show)
    this.element.addEventListener("mouseleave", this.scheduleHide)
    this.element.addEventListener("focusin", this.show)
    this.element.addEventListener("focusout", this.scheduleHide)
    this.element.addEventListener("click", this.toggle)

    if (this.hasTipTarget) {
      this.tipTarget.addEventListener("mouseenter", this.cancelHide)
      this.tipTarget.addEventListener("mouseleave", this.scheduleHide)
      this.tipTarget.addEventListener("focusin", this.cancelHide)
      this.tipTarget.addEventListener("focusout", this.scheduleHide)
    }
  }

  disconnect() {
    this.element.removeEventListener("mouseenter", this.show)
    this.element.removeEventListener("mouseleave", this.scheduleHide)
    this.element.removeEventListener("focusin", this.show)
    this.element.removeEventListener("focusout", this.scheduleHide)
    this.element.removeEventListener("click", this.toggle)

    if (this.hasTipTarget) {
      this.tipTarget.removeEventListener("mouseenter", this.cancelHide)
      this.tipTarget.removeEventListener("mouseleave", this.scheduleHide)
      this.tipTarget.removeEventListener("focusin", this.cancelHide)
      this.tipTarget.removeEventListener("focusout", this.scheduleHide)
    }

    this.removeGlobalListeners()
    this.destroyPopper()
  }

  show() {
    if (!this.hasTipTarget) return

    this.cancelHide()
    const tip = this.tipTarget
    tip.classList.remove("hidden")

    requestAnimationFrame(() => {
      this.ensurePopper()
      this.setPopperEventListeners(true)
      this.popper.update()
      tip.classList.add("opacity-100")
      tip.classList.remove("opacity-0")
      this.visible = true
      this.addGlobalListeners()
    })
  }

  hide() {
    if (!this.hasTipTarget) return

    this.cancelHide()
    const tip = this.tipTarget
    tip.classList.add("opacity-0")
    tip.classList.remove("opacity-100")
    this.visible = false
    this.removeGlobalListeners()
    this.setPopperEventListeners(false)

    this.hideTimeout = setTimeout(() => {
      if (!this.visible) tip.classList.add("hidden")
    }, 150)
  }

  toggle(event) {
    if (event.target.closest("a")) return

    event.preventDefault()
    this.visible ? this.hide() : this.show()
  }

  scheduleHide() {
    if (!this.hasTipTarget) return

    this.cancelHide()
    this.hideTimeout = setTimeout(() => {
      if (this.element.matches(":hover") || this.tipTarget.matches(":hover")) return
      if (this.element.contains(document.activeElement) || this.tipTarget.contains(document.activeElement)) return

      this.hide()
    }, 120)
  }

  cancelHide() {
    clearTimeout(this.hideTimeout)
  }

  hideOnOutsideClick(event) {
    if (this.element.contains(event.target) || this.tipTarget.contains(event.target)) return

    this.hide()
  }

  hideOnEscape(event) {
    if (event.key === "Escape") this.hide()
  }

  ensurePopper() {
    if (this.popper) return

    this.popper = createPopper(this.element, this.tipTarget, {
      placement: this.element.dataset.popoverTooltipPlacement || "top",
      strategy: "fixed",
      modifiers: [
        { name: "offset", options: { offset: [0, 8] } },
        { name: "flip", options: { padding: 8 } },
        { name: "preventOverflow", options: { padding: 8 } },
        { name: "arrow", options: { element: this.tipTarget.querySelector(".tooltip-arrow") } },
        { name: "eventListeners", enabled: false }
      ]
    })
  }

  setPopperEventListeners(enabled) {
    if (!this.popper) return

    this.popper.setOptions((options) => ({
      ...options,
      modifiers: [
        ...options.modifiers.filter((modifier) => modifier.name !== "eventListeners"),
        { name: "eventListeners", enabled }
      ]
    }))
  }

  destroyPopper() {
    if (!this.popper) return

    this.popper.destroy()
    this.popper = null
  }

  addGlobalListeners() {
    document.addEventListener("click", this.hideOnOutsideClick, true)
    document.addEventListener("keydown", this.hideOnEscape, true)
  }

  removeGlobalListeners() {
    document.removeEventListener("click", this.hideOnOutsideClick, true)
    document.removeEventListener("keydown", this.hideOnEscape, true)
  }
}
