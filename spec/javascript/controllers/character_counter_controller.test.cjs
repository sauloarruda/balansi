const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

function loadControllerClass() {
  const controllerPath = path.join(
    process.cwd(),
    "app/javascript/controllers/character_counter_controller.js"
  )

  const source = fs.readFileSync(controllerPath, "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"\n\n', "")
    .replace("export default class extends Controller {", "return class extends Controller {")

  return new Function("Controller", source)(class {})
}

function createClassList(initial = []) {
  const values = new Set(initial)

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

function buildController({
  value = "",
  maxLength = 140,
  withSpan = true
} = {}) {
  const CharacterCounterController = loadControllerClass()
  const controller = new CharacterCounterController()

  const listeners = {}
  const span = withSpan ? { textContent: "" } : null
  const counterTarget = {
    classList: createClassList(),
    querySelector(selector) {
      if (selector === "span") {
        return span
      }

      return null
    }
  }

  const inputTarget = {
    value,
    maxLength,
    added: null,
    removed: null,
    addEventListener(event, callback) {
      this.added = { event, callback }
      listeners[event] = callback
    },
    removeEventListener(event, callback) {
      this.removed = { event, callback }
      if (listeners[event] === callback) {
        delete listeners[event]
      }
    },
    trigger(event) {
      if (listeners[event]) {
        listeners[event]()
      }
    }
  }

  controller.hasInputTarget = true
  controller.hasCounterTarget = true
  controller.inputTarget = inputTarget
  controller.counterTarget = counterTarget

  return { controller, inputTarget, counterTarget, span }
}

test("connect initializes counter and toggles warning on input changes", () => {
  const { controller, inputTarget, counterTarget, span } = buildController({
    value: "abc",
    maxLength: 10
  })

  controller.connect()

  assert.equal(span.textContent, 3)
  assert.equal(inputTarget.added.event, "input")
  assert.equal(counterTarget.classList.contains("warning"), false)

  inputTarget.value = "0123456789"
  inputTarget.trigger("input")

  assert.equal(span.textContent, 10)
  assert.equal(counterTarget.classList.contains("warning"), true)
})

test("disconnect removes exactly the listener added during connect", () => {
  const { controller, inputTarget } = buildController({ value: "abc" })

  controller.connect()
  const addedCallback = inputTarget.added.callback
  controller.disconnect()

  assert.equal(inputTarget.removed.event, "input")
  assert.equal(inputTarget.removed.callback, addedCallback)
})

test("updateCounter does not fail when counter span is missing", () => {
  const { controller, counterTarget } = buildController({
    value: "abc",
    maxLength: 10,
    withSpan: false
  })

  assert.doesNotThrow(() => controller.updateCounter())
  assert.equal(counterTarget.classList.contains("warning"), false)
})
