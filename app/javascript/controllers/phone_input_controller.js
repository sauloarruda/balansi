import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["country", "number"]

  connect() {
    this.initializePhoneInput()
  }

  disconnect() {
    if (this.phoneInstance && typeof this.phoneInstance.destroy === "function") {
      this.phoneInstance.destroy()
    }

    if (this.countryChangeHandler && this.hasNumberTarget) {
      this.numberTarget.removeEventListener("countrychange", this.countryChangeHandler)
    }
  }

  numberChanged() {
    this.syncHiddenCountryFromPlugin()
  }

  initializePhoneInput() {
    if (!this.hasNumberTarget) return

    if (typeof window === "undefined" || typeof window.intlTelInput !== "function") {
      return
    }

    this.phoneInstance = window.intlTelInput(this.numberTarget, {
      initialCountry: this.initialCountry().toLowerCase(),
      preferredCountries: ["br", "us", "gb", "pt", "es", "fr", "ca"],
      nationalMode: true,
      separateDialCode: true,
      autoPlaceholder: "aggressive",
      formatAsYouType: true,
      loadUtils: () => import("https://cdn.jsdelivr.net/npm/intl-tel-input@25.12.3/build/js/utils.js")
    })

    this.countryChangeHandler = this.syncHiddenCountryFromPlugin.bind(this)
    this.numberTarget.addEventListener("countrychange", this.countryChangeHandler)
    this.syncHiddenCountryFromPlugin()
  }

  syncHiddenCountryFromPlugin() {
    if (!this.hasCountryTarget) return
    if (!this.phoneInstance || typeof this.phoneInstance.getSelectedCountryData !== "function") return

    const selectedCountry = this.phoneInstance.getSelectedCountryData()
    const iso2 = selectedCountry?.iso2 || this.initialCountry().toLowerCase()
    this.countryTarget.value = iso2.toUpperCase()
  }

  initialCountry() {
    if (!this.hasCountryTarget) return "BR"
    if (!this.countryTarget.value) return "BR"

    const normalized = this.countryTarget.value.toUpperCase()
    if (normalized.match(/^[A-Z]{2}$/)) {
      return normalized
    }

    return "BR"
  }
}
