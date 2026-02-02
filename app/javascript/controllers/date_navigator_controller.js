import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["datepickerInput", "display"]

  connect() {
    // Initialize Flowbite datepicker if available
    if (typeof window.Flowbite !== 'undefined' && this.hasDatepickerInputTarget) {
      this.initializeDatepicker()
    }
  }

  initializeDatepicker() {
    // Flowbite datepicker initialization
    // The datepicker will be initialized on the hidden input
    const datepickerEl = this.datepickerInputTarget
    
    if (window.Flowbite && window.Flowbite.Datepicker) {
      const datepicker = new window.Flowbite.Datepicker(datepickerEl, {
        format: 'yyyy-mm-dd',
        autohide: true
      })

      // Listen for date changes
      datepickerEl.addEventListener('changeDate', (e) => {
        const selectedDate = e.detail.date
        this.navigateToDate(selectedDate)
      })

      this.datepicker = datepicker
    }
  }

  previousDay() {
    const currentDate = this.getCurrentDate()
    const previousDate = new Date(currentDate)
    previousDate.setDate(previousDate.getDate() - 1)
    this.navigateToDate(previousDate)
  }

  nextDay() {
    const currentDate = this.getCurrentDate()
    const nextDate = new Date(currentDate)
    nextDate.setDate(nextDate.getDate() + 1)
    this.navigateToDate(nextDate)
  }

  openCalendar() {
    if (this.datepicker && this.hasDatepickerInputTarget) {
      this.datepicker.show()
    }
  }

  getCurrentDate() {
    // Extract date from current URL path (Rails route: /journals/YYYY-MM-DD)
    const pathMatch = window.location.pathname.match(/\/journals\/(\d{4}-\d{2}-\d{2})/)
    
    if (pathMatch && pathMatch[1]) {
      return new Date(pathMatch[1])
    }
    
    // Fallback to today
    return new Date()
  }

  navigateToDate(date) {
    // Format date as YYYY-MM-DD
    const formattedDate = date.toISOString().split('T')[0]
    
    // Navigate to Rails route: /journals/YYYY-MM-DD
    window.location.href = `/journals/${formattedDate}`
  }
}
