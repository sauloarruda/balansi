const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

function loadControllerClass() {
  const controllerPath = path.join(
    process.cwd(),
    "app/javascript/controllers/masked_input_controller.js"
  )

  const source = fs.readFileSync(controllerPath, "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"\n\n', "")
    .replace("export default class extends Controller {", "return class extends Controller {")

  return new Function("Controller", source)(class {})
}

function buildController(overrides = {}) {
  const MaskedInputController = loadControllerClass()

  const controller = new MaskedInputController()
  controller.element = { value: overrides.value || "" }
  controller.hasPatternValue = overrides.hasPattern !== undefined ? overrides.hasPattern : true
  controller.patternValue = overrides.pattern || "00/00/0000"
  controller.lazyValue = overrides.lazy !== undefined ? overrides.lazy : false
  controller.placeholderCharValue = overrides.placeholderChar || "_"

  return controller
}

test("connect initializes IMask with configured options", () => {
  const controller = buildController()
  let capturedOptions = null
  let destroyed = false

  global.IMask = (element, options) => {
    assert.equal(element, controller.element)
    capturedOptions = options
    return {
      destroy() {
        destroyed = true
      }
    }
  }

  controller.connect()
  assert.equal(capturedOptions.mask, "00/00/0000")
  assert.equal(capturedOptions.lazy, false)
  assert.equal(capturedOptions.placeholderChar, "_")
  assert.equal(capturedOptions.overwrite, true)

  controller.disconnect()
  assert.equal(destroyed, true)

  delete global.IMask
})

test("connect does nothing when no pattern is provided", () => {
  const controller = buildController({ hasPattern: false })
  let called = false

  global.IMask = () => {
    called = true
    return {}
  }

  controller.connect()
  assert.equal(called, false)

  delete global.IMask
})

test("connect does nothing when IMask is not loaded", () => {
  const controller = buildController()
  delete global.IMask

  controller.connect()
  assert.equal(controller.mask, undefined)
})
