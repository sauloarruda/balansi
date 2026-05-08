import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tip"]

  connect() {
    this.show = this.show.bind(this)
    this.hide = this.hide.bind(this)
    this.element.addEventListener("mouseenter", this.show)
    this.element.addEventListener("mouseleave", this.hide)
    this.element.addEventListener("focus", this.show)
    this.element.addEventListener("blur", this.hide)
  }

  disconnect() {
    this.element.removeEventListener("mouseenter", this.show)
    this.element.removeEventListener("mouseleave", this.hide)
    this.element.removeEventListener("focus", this.show)
    this.element.removeEventListener("blur", this.hide)
  }

  show() {
    if (!this.hasTipTarget) return
    const tip = this.tipTarget
    tip.classList.remove("hidden")
    // small delay to allow layout before positioning
    requestAnimationFrame(() => {
      this.position(tip)
      tip.classList.add("opacity-100")
      tip.classList.remove("opacity-0")
    })
  }

  hide() {
    if (!this.hasTipTarget) return
    const tip = this.tipTarget
    tip.classList.add("opacity-0")
    tip.classList.remove("opacity-100")
    setTimeout(() => tip.classList.add("hidden"), 150)
  }

  position(tip) {
    const rect = this.element.getBoundingClientRect()
    const tipRect = tip.getBoundingClientRect()
    const placement = this.element.dataset.tooltipPlacement || "top"

    let top, left

    switch (placement) {
      case "top":
        top = rect.top - tipRect.height - 6
        left = rect.left + (rect.width - tipRect.width) / 2
        break
      case "bottom":
        top = rect.bottom + 6
        left = rect.left + (rect.width - tipRect.width) / 2
        break
      case "left":
        top = rect.top + (rect.height - tipRect.height) / 2
        left = rect.left - tipRect.width - 6
        break
      case "right":
        top = rect.top + (rect.height - tipRect.height) / 2
        left = rect.right + 6
        break
      default:
        top = rect.top - tipRect.height - 6
        left = rect.left + (rect.width - tipRect.width) / 2
    }

    // viewport boundary checks
    const padding = 8
    if (left < padding) left = padding
    if (left + tipRect.width > window.innerWidth - padding) {
      left = window.innerWidth - tipRect.width - padding
    }
    if (top < padding) {
      // flip to bottom if not enough space on top
      top = rect.bottom + 6
      tip.dataset.tooltipPlacement = "bottom"
    } else {
      tip.dataset.tooltipPlacement = placement
    }

    tip.style.top = `${top + window.scrollY}px`
    tip.style.left = `${left + window.scrollX}px`
  }
}
