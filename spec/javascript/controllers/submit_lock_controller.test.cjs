const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

function loadControllerClass() {
  const controllerPath = path.join(
    process.cwd(),
    "app/javascript/controllers/submit_lock_controller.js"
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

function createButton(initialClasses = []) {
  return {
    disabled: false,
    classList: createClassList(initialClasses)
  }
}

test("disable locks all submit targets and updates visual state", () => {
  const SubmitLockController = loadControllerClass()
  const controller = new SubmitLockController()

  const firstButton = createButton(["cursor-pointer"])
  const secondButton = createButton(["cursor-pointer", "other-class"])
  controller.submitTargets = [firstButton, secondButton]

  controller.disable()

  ;[firstButton, secondButton].forEach((button) => {
    assert.equal(button.disabled, true)
    assert.equal(button.classList.contains("cursor-pointer"), false)
    assert.equal(button.classList.contains("cursor-not-allowed"), true)
    assert.equal(button.classList.contains("opacity-50"), true)
  })
})
