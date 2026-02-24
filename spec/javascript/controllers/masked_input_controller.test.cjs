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
  delete MaskedInputController.imaskLibraryPromise

  const controller = new MaskedInputController()
  controller.element = { value: overrides.value || "" }
  controller.hasPatternValue = overrides.hasPattern !== undefined ? overrides.hasPattern : true
  controller.patternValue = overrides.pattern || "00/00/0000"
  controller.lazyValue = overrides.lazy !== undefined ? overrides.lazy : false
  controller.placeholderCharValue = overrides.placeholderChar || "_"

  return controller
}

test("connect initializes IMask with configured options", async () => {
  const controller = buildController()
  let capturedOptions = null
  let destroyed = false

  controller.loadMaskLibrary = async () => (element, options) => {
    assert.equal(element, controller.element)
    capturedOptions = options
    return {
      destroy() {
        destroyed = true
      }
    }
  }

  await controller.connect()
  assert.equal(capturedOptions.mask, "00/00/0000")
  assert.equal(capturedOptions.lazy, false)
  assert.equal(capturedOptions.placeholderChar, "_")
  assert.equal(capturedOptions.overwrite, true)

  controller.disconnect()
  assert.equal(destroyed, true)
})

test("connect does nothing when no pattern is provided", async () => {
  const controller = buildController({ hasPattern: false })
  let libraryLoaded = false

  controller.loadMaskLibrary = async () => {
    libraryLoaded = true
    return () => ({})
  }

  await controller.connect()
  assert.equal(libraryLoaded, false)
})
