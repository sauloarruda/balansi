const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

function loadControllerClass(createPopper) {
  const controllerPath = path.join(
    process.cwd(),
    "app/javascript/controllers/popover_tooltip_controller.js"
  )

  const source = fs.readFileSync(controllerPath, "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"\n', "")
    .replace('import { createPopper } from "@popperjs/core"\n\n', "")
    .replace("export default class extends Controller {", "return class extends Controller {")

  return new Function("Controller", "createPopper", source)(class {}, createPopper)
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

function createEventTarget(extra = {}) {
  const listeners = {}

  return {
    listeners,
    addEventListener(type, callback) {
      listeners[type] = callback
    },
    removeEventListener(type, callback) {
      if (listeners[type] === callback) delete listeners[type]
    },
    contains(node) {
      return node === this
    },
    matches() {
      return false
    },
    ...extra
  }
}

test("click opens tooltip through Popper with scroll listeners enabled", () => {
  const originalDocument = global.document
  const originalRequestAnimationFrame = global.requestAnimationFrame

  global.requestAnimationFrame = (callback) => callback()
  global.document = createEventTarget({ activeElement: null })

  try {
    let popperOptions
    let currentOptions
    let updated = false

    const createPopper = (_element, _tip, options) => {
      popperOptions = options
      currentOptions = options

      return {
        update() {
          updated = true
        },
        setOptions(callback) {
          currentOptions = callback(currentOptions)
        },
        destroy() {}
      }
    }

    const PopoverTooltipController = loadControllerClass(createPopper)
    const controller = new PopoverTooltipController()
    const tip = createEventTarget({
      classList: createClassList(["hidden", "opacity-0"]),
      querySelector(selector) {
        return selector === ".tooltip-arrow" ? {} : null
      }
    })
    const element = createEventTarget({
      dataset: { popoverTooltipPlacement: "bottom" }
    })

    controller.element = element
    controller.tipTarget = tip
    controller.hasTipTarget = true
    controller.connect()

    element.listeners.click({
      target: { closest: () => null },
      preventDefault() {}
    })

    assert.equal(popperOptions.strategy, "fixed")
    assert.equal(popperOptions.placement, "bottom")
    assert.equal(updated, true)
    assert.equal(tip.classList.contains("hidden"), false)
    assert.equal(tip.classList.contains("opacity-100"), true)
    assert.equal(currentOptions.modifiers.find((modifier) => modifier.name === "eventListeners").enabled, true)
  } finally {
    global.document = originalDocument
    global.requestAnimationFrame = originalRequestAnimationFrame
  }
})
