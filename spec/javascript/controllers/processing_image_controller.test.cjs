const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

function loadControllerClass() {
  const controllerPath = path.join(
    process.cwd(),
    "app/javascript/controllers/processing_image_controller.js"
  )

  const source = fs.readFileSync(controllerPath, "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"\n\n', "")
    .replace("export default class extends Controller {", "return class extends Controller {")

  return new Function("Controller", source)(class {})
}

test("reload swaps the placeholder src after the real image loads", () => {
  const ProcessingImageController = loadControllerClass()
  const controller = new ProcessingImageController()
  const previousImage = global.Image
  const previousWindow = global.window
  const previousDateNow = Date.now

  global.window = { location: { origin: "http://example.test" } }
  Date.now = () => 123
  global.Image = class {
    set src(value) {
      this._src = value
      this.onload()
    }

    get src() {
      return this._src
    }
  }

  controller.element = { src: "/assets/image-processing.svg" }
  controller.srcValue = "/rails/active_storage/representations/image"
  controller.hasSrcValue = true
  controller.hasIntervalValue = false

  try {
    controller.reload()

    assert.equal(
      controller.element.src,
      "http://example.test/rails/active_storage/representations/image?processing_image_retry=123"
    )
  } finally {
    global.Image = previousImage
    global.window = previousWindow
    Date.now = previousDateNow
  }
})

test("reload schedules another attempt when the real image still fails", () => {
  const ProcessingImageController = loadControllerClass()
  const controller = new ProcessingImageController()
  const previousImage = global.Image
  const previousWindow = global.window
  const previousSetTimeout = global.setTimeout
  const previousClearTimeout = global.clearTimeout
  let scheduledDelay

  global.window = { location: { origin: "http://example.test" } }
  global.setTimeout = (_callback, delay) => {
    scheduledDelay = delay
    return 1
  }
  global.clearTimeout = () => {}
  global.Image = class {
    set src(_value) {
      this.onerror()
    }
  }

  controller.element = { src: "/assets/image-processing.svg" }
  controller.srcValue = "/rails/active_storage/representations/image"
  controller.hasSrcValue = true
  controller.intervalValue = 500
  controller.hasIntervalValue = true

  try {
    controller.reload()

    assert.equal(scheduledDelay, 500)
  } finally {
    global.Image = previousImage
    global.window = previousWindow
    global.setTimeout = previousSetTimeout
    global.clearTimeout = previousClearTimeout
  }
})
