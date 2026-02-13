const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

function loadControllerClass() {
  const controllerPath = path.join(
    process.cwd(),
    "app/javascript/controllers/date_navigator_controller.js"
  )

  const source = fs.readFileSync(controllerPath, "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"\n\n', "")
    .replace("export default class extends Controller {", "return class extends Controller {")

  return new Function("Controller", source)(class {})
}

function createClassList() {
  const values = new Set()

  return {
    add(...tokens) {
      tokens.forEach((token) => values.add(token))
    },
    remove(...tokens) {
      tokens.forEach((token) => values.delete(token))
    },
    contains(token) {
      return values.has(token)
    }
  }
}

function createButton() {
  return {
    disabled: false,
    classList: createClassList()
  }
}

function buildController(overrides = {}) {
  const DateNavigatorController = loadControllerClass()
  const controller = new DateNavigatorController()

  const previousButton = createButton()
  const nextButton = createButton()

  controller.hasCurrentDateValue = true
  controller.currentDateValue = overrides.currentDateValue || toIsoDate(new Date())

  controller.hasCalendarInputTarget = true
  controller.calendarInputTarget = {
    value: "",
    max: "",
    showPickerCalled: false,
    focused: false,
    clicked: false,
    showPicker() {
      this.showPickerCalled = true
    },
    focus() {
      this.focused = true
    },
    click() {
      this.clicked = true
    }
  }

  controller.hasPreviousButtonTarget = true
  controller.previousButtonTarget = previousButton
  controller.hasNextButtonTarget = true
  controller.nextButtonTarget = nextButton

  if (Object.prototype.hasOwnProperty.call(overrides, "hasShowPicker") && !overrides.hasShowPicker) {
    delete controller.calendarInputTarget.showPicker
  }

  global.window = {
    location: {
      href: "",
      pathname: "/journals/today"
    },
  }

  return {
    controller,
    previousButton,
    nextButton,
    calendarInput: controller.calendarInputTarget
  }
}

function toIsoDate(date) {
  const year = date.getFullYear()
  const month = `${date.getMonth() + 1}`.padStart(2, "0")
  const day = `${date.getDate()}`.padStart(2, "0")
  return `${year}-${month}-${day}`
}

test("connect initializes calendar max/value and disables next button when on today", () => {
  const today = new Date()
  const { controller, nextButton, calendarInput } = buildController({
    currentDateValue: toIsoDate(today)
  })

  controller.connect()

  assert.equal(calendarInput.max, toIsoDate(today))
  assert.equal(calendarInput.value, toIsoDate(today))
  assert.equal(nextButton.disabled, true)
  assert.equal(nextButton.classList.contains("cursor-not-allowed"), true)
})

test("previousDay navigates to previous journal date and disables arrow buttons", () => {
  const baseDate = new Date()
  baseDate.setDate(baseDate.getDate() - 2)

  const { controller, previousButton, nextButton } = buildController({
    currentDateValue: toIsoDate(baseDate)
  })

  controller.connect()
  controller.previousDay()

  const expectedDate = new Date(baseDate)
  expectedDate.setDate(expectedDate.getDate() - 1)

  assert.equal(global.window.location.href, `/journals/${toIsoDate(expectedDate)}`)
  assert.equal(previousButton.disabled, true)
  assert.equal(nextButton.disabled, true)
})

test("nextDay does not navigate when already at today", () => {
  const today = new Date()
  const { controller } = buildController({
    currentDateValue: toIsoDate(today)
  })

  controller.connect()
  controller.nextDay()

  assert.equal(global.window.location.href, "")
})

test("onCalendarChange clamps future selected date to today", () => {
  const today = new Date()
  const tomorrow = new Date(today)
  tomorrow.setDate(today.getDate() + 1)

  const { controller, calendarInput } = buildController({
    currentDateValue: toIsoDate(today)
  })

  controller.connect()
  calendarInput.value = toIsoDate(tomorrow)
  controller.onCalendarChange()

  assert.equal(global.window.location.href, `/journals/${toIsoDate(today)}`)
})

test("openCalendar uses showPicker when available and fallback otherwise", () => {
  const { controller, calendarInput } = buildController()
  controller.connect()
  controller.openCalendar()

  assert.equal(calendarInput.showPickerCalled, true)

  const fallback = buildController({ hasShowPicker: false })
  fallback.controller.connect()
  fallback.controller.openCalendar()

  assert.equal(fallback.calendarInput.focused, true)
  assert.equal(fallback.calendarInput.clicked, true)
})
