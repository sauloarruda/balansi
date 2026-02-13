import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["calendarInput", "previousButton", "nextButton"]
  static values = { currentDate: String }

  connect() {
    this.maxDate = this.startOfDay(new Date())
    this.currentDate = this.resolveCurrentDate()

    if (this.currentDate > this.maxDate) {
      this.currentDate = this.maxDate
    }

    if (this.hasCalendarInputTarget) {
      this.calendarInputTarget.max = this.toIsoDate(this.maxDate)
      this.calendarInputTarget.value = this.toIsoDate(this.currentDate)
    }

    this.refreshNavigationControls()
  }

  onCalendarChange() {
    if (!this.hasCalendarInputTarget || !this.calendarInputTarget.value) {
      return
    }

    const selectedDate = this.parseIsoDate(this.calendarInputTarget.value)
    if (!selectedDate) {
      return
    }

    this.navigateToDate(selectedDate)
  }

  previousDay() {
    this.navigateByDays(-1)
  }

  nextDay() {
    if (this.currentDate >= this.maxDate) {
      this.refreshNavigationControls()
      return
    }

    this.navigateByDays(1)
  }

  openCalendar() {
    if (!this.hasCalendarInputTarget) {
      return
    }

    if (typeof this.calendarInputTarget.showPicker === "function") {
      this.calendarInputTarget.showPicker()
      return
    }

    this.calendarInputTarget.focus()
    this.calendarInputTarget.click()
  }

  resolveCurrentDate() {
    if (this.hasCurrentDateValue) {
      const parsedCurrentDate = this.parseIsoDate(this.currentDateValue)
      if (parsedCurrentDate) {
        return parsedCurrentDate
      }
    }

    const pathMatch = window.location.pathname.match(/\/journals\/(\d{4}-\d{2}-\d{2})/)

    if (pathMatch && pathMatch[1]) {
      const parsedPathDate = this.parseIsoDate(pathMatch[1])
      if (parsedPathDate) {
        return parsedPathDate
      }
    }

    return this.maxDate
  }

  navigateByDays(days) {
    this.disableArrowButtons()

    const targetDate = new Date(this.currentDate)
    targetDate.setDate(targetDate.getDate() + days)
    this.navigateToDate(targetDate)
  }

  navigateToDate(date) {
    const targetDate = date > this.maxDate ? this.maxDate : date
    const formattedDate = this.toIsoDate(targetDate)
    window.location.href = `/journals/${formattedDate}`
  }

  parseIsoDate(isoDate) {
    const dateMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(isoDate)
    if (!dateMatch) {
      return null
    }

    const year = Number(dateMatch[1])
    const month = Number(dateMatch[2])
    const day = Number(dateMatch[3])

    const parsedDate = new Date(year, month - 1, day)
    if (!this.isValidDateParts(parsedDate, year, month, day)) {
      return null
    }

    return parsedDate
  }

  isValidDateParts(date, year, month, day) {
    return date.getFullYear() === year &&
      date.getMonth() + 1 === month &&
      date.getDate() === day
  }

  toIsoDate(date) {
    const year = date.getFullYear()
    const month = `${date.getMonth() + 1}`.padStart(2, "0")
    const day = `${date.getDate()}`.padStart(2, "0")
    return `${year}-${month}-${day}`
  }

  startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate())
  }

  disableArrowButtons() {
    if (this.hasPreviousButtonTarget) {
      this.setButtonState(this.previousButtonTarget, true)
    }

    if (this.hasNextButtonTarget) {
      this.setButtonState(this.nextButtonTarget, true)
    }
  }

  refreshNavigationControls() {
    if (this.hasPreviousButtonTarget) {
      this.setButtonState(this.previousButtonTarget, false)
    }

    if (this.hasNextButtonTarget) {
      this.setButtonState(this.nextButtonTarget, this.currentDate >= this.maxDate)
    }
  }

  setButtonState(button, disabled) {
    if (!button) {
      return
    }

    button.disabled = disabled

    if (disabled) {
      button.classList.remove("cursor-pointer")
      button.classList.add("cursor-not-allowed", "opacity-50")
      return
    }

    button.classList.remove("cursor-not-allowed", "opacity-50")
    button.classList.add("cursor-pointer")
  }
}
