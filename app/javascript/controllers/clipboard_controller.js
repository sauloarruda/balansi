import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    text: String,
    successMessage: String,
    errorMessage: String
  }

  async copy() {
    try {
      await this.writeText(this.textValue)
      this.showToast(this.successMessageValue, "success")
    } catch (_error) {
      this.showToast(this.errorMessageValue, "error")
    }
  }

  async writeText(text) {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text)
      return
    }

    const textArea = document.createElement("textarea")
    textArea.value = text
    textArea.setAttribute("readonly", "")
    textArea.classList.add("fixed", "left-[-9999px]", "top-0")
    document.body.appendChild(textArea)
    textArea.select()

    const copied = document.execCommand("copy")
    textArea.remove()

    if (!copied) throw new Error("Copy command failed")
  }

  showToast(message, type) {
    const toast = document.createElement("div")
    toast.className = this.toastClasses(type)
    toast.setAttribute("role", "status")
    toast.textContent = message
    document.body.appendChild(toast)

    window.setTimeout(() => {
      toast.classList.add("opacity-0")
      window.setTimeout(() => toast.remove(), 200)
    }, 2500)
  }

  toastClasses(type) {
    const colorClasses = type === "success" ?
      "bg-green-50 border-green-200 text-green-800" :
      "bg-red-50 border-red-200 text-red-800"

    return [
      "fixed", "bottom-4", "right-4", "z-50", "max-w-sm",
      "rounded-lg", "border", "px-4", "py-3", "shadow-lg",
      "transition-opacity", "duration-200", colorClasses
    ].join(" ")
  }
}
