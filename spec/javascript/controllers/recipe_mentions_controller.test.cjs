const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

function loadControllerClass() {
  const controllerPath = path.join(
    process.cwd(),
    "app/javascript/controllers/recipe_mentions_controller.js"
  )

  const source = fs.readFileSync(controllerPath, "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"\n\n', "")
    .replace("export default class extends Controller {", "return class extends Controller {")

  return new Function("Controller", source)(class {})
}

function textNode(text) {
  return { nodeType: Node.TEXT_NODE, textContent: text }
}

function elementNode({ tagName = "SPAN", dataset = {}, childNodes = [] } = {}) {
  return {
    nodeType: Node.ELEMENT_NODE,
    tagName,
    dataset,
    childNodes,
    attributes: {},
    className: "",
    classList: {
      add() {},
      remove() {},
      toggle() {}
    },
    _textContent: undefined,
    get textContent() {
      if (this._textContent !== undefined) return this._textContent

      return this.childNodes.map((child) => child.textContent).join("")
    },
    set textContent(value) {
      this._textContent = value
    },
    appendChild(child) {
      this.childNodes.push(child)
      return child
    },
    replaceChildren(...children) {
      this.childNodes = children
    },
    matches(selector) {
      return selector === "[data-recipe-id]" && Boolean(this.dataset.recipeId)
    },
    setAttribute(name, value) {
      this.attributes[name] = value
    },
    getAttribute(name) {
      return this.attributes[name]
    },
    querySelector(selector) {
      return this.querySelectorAll(selector)[0] || null
    },
    querySelectorAll(selector) {
      const matches = []
      const visit = (node) => {
        if (node.nodeType !== Node.ELEMENT_NODE) return
        if (selector === "[data-recipe-result]" && node.dataset.recipeResult) matches.push(node)
        node.childNodes.forEach(visit)
      }

      this.childNodes.forEach(visit)
      return matches
    },
    closest() {
      return null
    }
  }
}

function setReferenceFormat(controller) {
  controller.referencePrefixValue = "@["
  controller.referenceMiddleValue = "](recipe:"
  controller.referenceSuffixValue = ")"
}

global.Node = { TEXT_NODE: 3, ELEMENT_NODE: 1 }
global.document = {
  createElement(tagName) {
    return elementNode({ tagName: tagName.toUpperCase() })
  },
  createElementNS(_namespace, tagName) {
    return elementNode({ tagName: tagName.toUpperCase() })
  },
  createTextNode: textNode
}
global.Event = class Event {
  constructor(type) {
    this.type = type
  }
}
global.AbortController = class AbortController {
  constructor() {
    this.signal = {}
  }

  abort() {}
}

test("structuredReference removes parser delimiters from recipe names", () => {
  const RecipeMentionsController = loadControllerClass()
  const controller = new RecipeMentionsController()
  setReferenceFormat(controller)

  assert.equal(
    controller.structuredReference({ id: 7, name: "Bolo [teste] (caseiro)" }),
    "@[Bolo teste caseiro](recipe:7)"
  )
})

test("serializeNode turns visual recipe chips into structured references", () => {
  const RecipeMentionsController = loadControllerClass()
  const controller = new RecipeMentionsController()
  setReferenceFormat(controller)
  controller.gramsTextValue = "g"
  const chip = controller.chipElement({
    id: "123",
    name: "Bolo de banana",
    portion_size_grams: 180
  })
  const editor = elementNode({
    tagName: "DIV",
    childNodes: [
      textNode("Comi "),
      chip,
      textNode(" hoje")
    ]
  })

  assert.equal(chip.textContent, "Bolo de banana (180g)")
  assert.equal(chip.className, "inline-flex")
  assert.equal(chip.childNodes[0].className, "recipe-mention-chip")
  assert.equal(controller.serializeNode(editor), "Comi @[Bolo de banana](recipe:123) hoje")
})

test("chipElement includes a tooltip when recipe nutrition is available", () => {
  const RecipeMentionsController = loadControllerClass()
  const controller = new RecipeMentionsController()
  controller.gramsTextValue = "g"
  controller.kcalTextValue = "kcal"

  const chip = controller.chipElement({
    id: "123",
    name: "Bolo de banana",
    portion_size_grams: 180,
    calories_per_portion: 320,
    proteins_per_portion: 8,
    carbs_per_portion: 52,
    fats_per_portion: 9
  })

  assert.equal(chip.dataset.controller, "popover-tooltip")
  assert.equal(chip.childNodes[1].dataset.popoverTooltipTarget, "tip")
  assert.match(chip.textContent, /320/)
  assert.match(chip.textContent, /52g/)
})

test("serializedValue trims editor value and normalizes non-breaking spaces", () => {
  const RecipeMentionsController = loadControllerClass()
  const controller = new RecipeMentionsController()

  controller.hasEditorTarget = true
  controller.editorTarget = elementNode({
    tagName: "DIV",
    childNodes: [textNode("  Iogurte\u00a0com fruta  ")]
  })

  assert.equal(controller.serializedValue(), "Iogurte com fruta")
})

test("syncField stores serialized editor content in the hidden form field", () => {
  const RecipeMentionsController = loadControllerClass()
  const controller = new RecipeMentionsController()

  controller.hasEditorTarget = true
  controller.editorTarget = elementNode({
    tagName: "DIV",
    childNodes: [textNode("Almoco")]
  })
  controller.hasFieldTarget = true
  controller.fieldTarget = { value: "" }

  controller.syncField()

  assert.equal(controller.fieldTarget.value, "Almoco")
})

test("renderEditorFromField turns saved structured references into visual chips", () => {
  const RecipeMentionsController = loadControllerClass()
  const controller = new RecipeMentionsController()
  setReferenceFormat(controller)

  controller.hasEditorTarget = true
  controller.editorTarget = elementNode({ tagName: "DIV" })
  controller.hasFieldTarget = true
  controller.fieldTarget = { value: "Comi @[Bolo de banana](recipe:123) hoje" }
  controller.gramsTextValue = "g"
  controller.initialRecipesValue = [{ id: 123, portion_size_grams: 180 }]

  controller.renderEditorFromField()

  assert.equal(controller.editorTarget.childNodes.length, 3)
  assert.equal(controller.editorTarget.childNodes[0].textContent, "Comi ")
  assert.equal(controller.editorTarget.childNodes[1].dataset.recipeId, "123")
  assert.equal(controller.editorTarget.childNodes[1].dataset.recipeName, "Bolo de banana")
  assert.equal(controller.editorTarget.childNodes[1].dataset.recipePortionSizeGrams, 180)
  assert.equal(controller.editorTarget.childNodes[1].className, "inline-flex")
  assert.equal(controller.editorTarget.childNodes[1].childNodes[0].className, "recipe-mention-chip")
  assert.equal(controller.editorTarget.childNodes[1].textContent, "Bolo de banana (180g)")
  assert.equal(controller.editorTarget.childNodes[2].textContent, " hoje")
  assert.equal(controller.serializedValue(), "Comi @[Bolo de banana](recipe:123) hoje")
})

test("search requests recent recipes for an empty mention query", async () => {
  const RecipeMentionsController = loadControllerClass()
  const controller = new RecipeMentionsController()
  let requestedUrl = null

  global.window = { location: { origin: "http://example.test" } }
  global.fetch = async (url) => {
    requestedUrl = url.toString()
    return { ok: true, json: async () => [] }
  }

  controller.searchUrlValue = "/patient/recipes/search"
  controller.showResults = () => {}

  await controller.search("")

  assert.equal(
    requestedUrl,
    "http://example.test/patient/recipes/search?q=&recent=true"
  )
})

test("scheduleSearch waits 500ms before searching", () => {
  const RecipeMentionsController = loadControllerClass()
  const controller = new RecipeMentionsController()
  const originalSetTimeout = global.setTimeout
  let delay = null

  global.setTimeout = (_callback, timeout) => {
    delay = timeout
    return 1
  }

  controller.showStatus = () => {}
  controller.search = () => {}
  controller.loadingTextValue = "Searching..."

  try {
    controller.scheduleSearch("iog")
  } finally {
    global.setTimeout = originalSetTimeout
  }

  assert.equal(delay, 500)
})

test("appendCreateRecipeButton adds a fixed create recipe action to the actions footer", () => {
  const RecipeMentionsController = loadControllerClass()
  const controller = new RecipeMentionsController()
  const actions = elementNode({ tagName: "DIV" })

  controller.hasActionsTarget = true
  controller.actionsTarget = actions
  controller.hasNewRecipeUrlValue = true
  controller.createRecipeTextValue = "Create new recipe"

  controller.appendCreateRecipeButton()

  assert.equal(actions.childNodes.length, 1)
  assert.equal(actions.childNodes[0].textContent, "Create new recipe")
  assert.equal(actions.childNodes[0].dataset.action, "mousedown->recipe-mentions#createRecipe")
})

test("createRecipe stores the meal form draft and redirects to the recipe form", () => {
  const RecipeMentionsController = loadControllerClass()
  const controller = new RecipeMentionsController()
  const stored = {}
  const redirectedTo = []
  const descriptionField = {
    name: "meal[description]",
    type: "hidden",
    value: "",
    checked: false,
    multiple: false
  }
  const mealTypeField = {
    name: "meal[meal_type]",
    type: "select-one",
    value: "lunch",
    checked: false,
    multiple: false
  }
  const form = {
    querySelectorAll() {
      return [descriptionField, mealTypeField]
    }
  }

  global.window = {
    location: {
      origin: "http://example.test",
      href: "http://example.test/journals/2026-05-15/meals/new",
      pathname: "/journals/2026-05-15/meals/new",
      search: ""
    },
    sessionStorage: {
      setItem(key, value) {
        stored[key] = value
      }
    }
  }
  global.window.location.assign = (url) => redirectedTo.push(url)
  controller.element = { closest: () => form }
  controller.hasEditorTarget = true
  controller.editorTarget = elementNode({ tagName: "DIV", childNodes: [textNode("Comi @Bolo")] })
  controller.hasFieldTarget = true
  controller.fieldTarget = descriptionField
  controller.newRecipeUrlValue = "/patient/recipes/new"
  controller.activeQuery = "Bolo"

  controller.createRecipe({ preventDefault() {} })

  const storedDraft = JSON.parse(stored["balansi:recipe-mentions:form-draft:/journals/2026-05-15/meals/new"])
  const url = new URL(redirectedTo[0])

  assert.equal(storedDraft.fields.find((field) => field.name === "meal[description]").value, "Comi @Bolo")
  assert.equal(storedDraft.fields.find((field) => field.name === "meal[meal_type]").value, "lunch")
  assert.equal(url.pathname, "/patient/recipes/new")
  assert.equal(url.searchParams.get("recipe[name]"), "Bolo")
  assert.equal(url.searchParams.get("return_to"), "http://example.test/journals/2026-05-15/meals/new")
})

test("restoreFormDraft restores saved form fields", () => {
  const RecipeMentionsController = loadControllerClass()
  const controller = new RecipeMentionsController()
  const descriptionField = {
    name: "meal[description]",
    type: "hidden",
    value: "",
    checked: false,
    multiple: false,
    dispatchEvent() {}
  }
  const mealTypeField = {
    name: "meal[meal_type]",
    type: "select-one",
    value: "breakfast",
    checked: false,
    multiple: false,
    dispatchEvent() {}
  }
  const form = {
    querySelectorAll() {
      return [descriptionField, mealTypeField]
    }
  }
  const key = "balansi:recipe-mentions:form-draft:/journals/2026-05-15/meals/new"
  const stored = {
    [key]: JSON.stringify({
      fields: [
        { name: "meal[description]", type: "hidden", value: "Comi @[Bolo](recipe:1)", checked: false, multiple: false },
        { name: "meal[meal_type]", type: "select-one", value: "snack", checked: false, multiple: false }
      ]
    })
  }

  global.window = {
    location: {
      pathname: "/journals/2026-05-15/meals/new",
      search: ""
    },
    sessionStorage: {
      getItem(keyName) {
        return stored[keyName]
      },
      removeItem(keyName) {
        delete stored[keyName]
      }
    }
  }
  controller.element = { closest: () => form }

  controller.restoreFormDraft()

  assert.equal(descriptionField.value, "Comi @[Bolo](recipe:1)")
  assert.equal(mealTypeField.value, "snack")
  assert.equal(stored[key], undefined)
})
