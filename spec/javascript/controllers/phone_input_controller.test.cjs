const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

function loadControllerClass() {
  const controllerPath = path.join(
    process.cwd(),
    "app/javascript/controllers/phone_input_controller.js"
  )

  const source = fs.readFileSync(controllerPath, "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"\n\n', "")
    .replace("export default class extends Controller {", "return class extends Controller {")

  return new Function("Controller", source)(class {})
}

function createNumberField(value = "") {
  const listeners = new Map()

  return {
    value,
    addEventListener(event, handler) {
      listeners.set(event, handler)
    },
    removeEventListener(event) {
      listeners.delete(event)
    },
    dispatch(event) {
      if (listeners.has(event)) listeners.get(event)()
    },
    hasListener(event) {
      return listeners.has(event)
    }
  }
}

function buildController(overrides = {}) {
  const PhoneInputController = loadControllerClass()
  const controller = new PhoneInputController()

  controller.hasCountryTarget = true
  controller.countryTarget = { value: overrides.country || "BR" }

  controller.hasNumberTarget = true
  controller.numberTarget = createNumberField(overrides.number || "")

  return controller
}

test("connect initializes intl-tel-input and syncs selected country", () => {
  const controller = buildController({ country: "BR", number: "11999999999" })

  let capturedOptions = null
  let destroyed = false

  global.window = {
    intlTelInput(input, options) {
      capturedOptions = options
      assert.equal(input, controller.numberTarget)
      return {
        getSelectedCountryData() {
          return { iso2: "us" }
        },
        destroy() {
          destroyed = true
        }
      }
    }
  }

  controller.connect()
  assert.equal(capturedOptions.initialCountry, "br")
  assert.equal(controller.countryTarget.value, "US")
  assert.equal(controller.numberTarget.hasListener("countrychange"), true)

  controller.disconnect()
  assert.equal(destroyed, true)
  assert.equal(controller.numberTarget.hasListener("countrychange"), false)
})

test("numberChanged keeps hidden country in sync with plugin country", () => {
  const controller = buildController({ country: "BR" })

  global.window = {
    intlTelInput() {
      return {
        getSelectedCountryData() {
          return { iso2: "fr" }
        },
        destroy() {}
      }
    }
  }

  controller.connect()
  controller.numberChanged()

  assert.equal(controller.countryTarget.value, "FR")
})
