import { Controller } from "@hotwired/stimulus"

const SEARCH_DEBOUNCE_MS = 500

export default class extends Controller {
  static targets = ["editor", "field", "panel", "list", "status"]
  static values = {
    searchUrl: String,
    loadingText: String,
    noResultsText: String,
    errorText: String,
    kcalText: String,
    gramsText: String,
    carbsText: String,
    proteinText: String,
    fatsText: String,
    referencePrefix: String,
    referenceMiddle: String,
    referenceSuffix: String,
    initialRecipes: Array
  }

  connect() {
    this.recipes = []
    this.selectedIndex = -1
    this.debounceTimeout = null
    this.abortController = null
    this.renderEditorFromField()
    this.syncField()
    this.editorTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  disconnect() {
    clearTimeout(this.debounceTimeout)
    this.abortSearch()
  }

  input() {
    this.syncField()
    const mention = this.currentMention()

    if (!mention) {
      clearTimeout(this.debounceTimeout)
      this.abortSearch()
      this.hidePanel()
      return
    }

    this.showPanel()
    this.scheduleSearch(mention.query.trim())
  }

  keydown(event) {
    if (!this.isPanelOpen()) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.hidePanel()
      return
    }

    if (this.recipes.length === 0) return

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.selectIndex(this.selectedIndex + 1)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.selectIndex(this.selectedIndex - 1)
    } else if ((event.key === "Enter" || event.key === "Tab") && this.selectedIndex >= 0) {
      event.preventDefault()
      this.insertRecipe(this.recipes[this.selectedIndex])
    }
  }

  paste(event) {
    event.preventDefault()
    document.execCommand("insertText", false, event.clipboardData.getData("text/plain"))
  }

  blur() {
    setTimeout(() => this.hidePanel(), 100)
  }

  keepFocus(event) {
    event.preventDefault()
  }

  select(event) {
    const recipe = this.recipes[event.params.index]
    if (recipe) this.insertRecipe(recipe)
  }

  currentMention() {
    if (!this.hasEditorTarget) return null

    const selection = window.getSelection()
    if (!selection || !selection.isCollapsed || selection.rangeCount === 0) return null

    const range = selection.getRangeAt(0)
    if (!this.editorTarget.contains(range.startContainer)) return null
    if (range.startContainer.nodeType !== Node.TEXT_NODE) return null

    const textBeforeCursor = range.startContainer.textContent.slice(0, range.startOffset)
    const atIndex = textBeforeCursor.lastIndexOf("@")

    if (atIndex < 0) return null
    if (atIndex > 0 && !/\s/.test(textBeforeCursor[atIndex - 1])) return null

    const query = textBeforeCursor.slice(atIndex + 1)
    if (/[\n\r@()[\]]/.test(query)) return null
    if (query.length > 80) return null

    const mentionRange = document.createRange()
    mentionRange.setStart(range.startContainer, atIndex)
    mentionRange.setEnd(range.startContainer, range.startOffset)

    return { range: mentionRange, query }
  }

  insertRecipe(recipe) {
    const mention = this.currentMention()
    if (!mention) return

    const trailingText = this.trailingTextFor(mention.range)
    const needsSpace = trailingText.length === 0 || !/^\s/.test(trailingText)
    const chip = this.chipElement(recipe)
    const fragment = document.createDocumentFragment()
    let caretNode = chip

    fragment.appendChild(chip)

    if (needsSpace) {
      caretNode = document.createTextNode(" ")
      fragment.appendChild(caretNode)
    }

    mention.range.deleteContents()
    mention.range.insertNode(fragment)
    this.placeCaretAfter(caretNode)
    this.syncField()
    this.editorTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.editorTarget.focus()
    this.hidePanel()
  }

  chipElement(recipe) {
    const chip = document.createElement("span")
    chip.contentEditable = "false"
    chip.dataset.controller = "popover-tooltip"
    chip.dataset.popoverTooltipPlacement = "top"
    chip.dataset.recipeId = recipe.id
    chip.dataset.recipeName = recipe.name
    chip.className = "inline-flex"

    if (recipe.portion_size_grams) chip.dataset.recipePortionSizeGrams = recipe.portion_size_grams

    const button = document.createElement("button")
    button.type = "button"
    button.className = "recipe-mention-chip"
    button.textContent = this.chipText(recipe)
    chip.appendChild(button)

    if (this.hasRecipeNutrition(recipe)) {
      chip.appendChild(this.recipeTooltipElement(recipe))
    }

    return chip
  }

  recipeTooltipElement(recipe) {
    const tooltip = document.createElement("span")
    tooltip.className = "tooltip hidden opacity-0 transition-opacity duration-150 fixed z-50 rounded-lg bg-gray-900 p-3 text-left text-sm text-white shadow-lg w-max max-w-[calc(100vw-2rem)]"
    tooltip.dataset.popoverTooltipTarget = "tip"
    tooltip.setAttribute("role", "tooltip")

    const body = document.createElement("span")
    body.className = "block space-y-3"

    const header = document.createElement("span")
    header.className = "block"

    const name = document.createElement("span")
    name.className = "block font-semibold leading-5"
    name.textContent = recipe.name
    header.appendChild(name)

    const portion = document.createElement("span")
    portion.className = "mt-0.5 block text-xs text-gray-300"
    portion.textContent = `${this.formatNumber(recipe.portion_size_grams, 2)}${this.gramsTextValue || "g"}`
    header.appendChild(portion)

    body.appendChild(header)
    body.appendChild(this.recipeNutritionStripElement(recipe))
    tooltip.appendChild(body)

    const arrow = document.createElement("span")
    arrow.className = "tooltip-arrow"
    tooltip.appendChild(arrow)

    return tooltip
  }

  recipeNutritionStripElement(recipe) {
    const strip = document.createElement("span")
    strip.className = "flex items-center gap-3 rounded-base border border-pink-100 bg-pink-50 px-3 py-2 text-gray-900"

    const calories = document.createElement("span")
    calories.className = "shrink-0"

    const calorieValue = document.createElement("span")
    calorieValue.className = "text-body font-bold text-pink-900"
    calorieValue.textContent = this.formatNumber(recipe.calories_per_portion, 2)
    calories.appendChild(calorieValue)

    const calorieUnit = document.createElement("span")
    calorieUnit.className = "text-xs text-pink-600 ml-0.5"
    calorieUnit.textContent = this.kcalTextValue || "kcal"
    calories.appendChild(calorieUnit)
    strip.appendChild(calories)

    const portion = document.createElement("span")
    portion.className = "shrink-0"

    const portionValue = document.createElement("span")
    portionValue.className = "text-xs font-bold text-gray-500"
    portionValue.textContent = `${this.formatNumber(recipe.portion_size_grams, 2)}${this.gramsTextValue || "g"}`
    portion.appendChild(portionValue)
    strip.appendChild(portion)

    strip.appendChild(this.macroCirclesElement(recipe))

    return strip
  }

  macroCirclesElement(recipe) {
    const wrapper = document.createElement("span")
    wrapper.className = "flex items-center gap-3"

    wrapper.appendChild(this.macroCircleElement(recipe, recipe.carbs_per_portion, this.carbsTextValue, "ring-carbs", "#92400e"))
    wrapper.appendChild(this.macroCircleElement(recipe, recipe.proteins_per_portion, this.proteinTextValue, "ring-protein", "#1e3a8a"))
    wrapper.appendChild(this.macroCircleElement(recipe, recipe.fats_per_portion, this.fatsTextValue, "ring-fat", "#9d174d"))

    return wrapper
  }

  macroCircleElement(recipe, value, label, ringClass, textColor) {
    const item = document.createElement("span")
    item.className = "flex items-center gap-1.5"

    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    svg.setAttribute("width", "44")
    svg.setAttribute("height", "44")
    svg.setAttribute("viewBox", "0 0 36 36")

    const group = document.createElementNS("http://www.w3.org/2000/svg", "g")
    group.setAttribute("transform", "rotate(-90 18 18)")

    const bg = document.createElementNS("http://www.w3.org/2000/svg", "circle")
    bg.setAttribute("class", "macro-ring-bg")
    bg.setAttribute("cx", "18")
    bg.setAttribute("cy", "18")
    bg.setAttribute("r", "15.9")
    group.appendChild(bg)

    const ring = document.createElementNS("http://www.w3.org/2000/svg", "circle")
    ring.setAttribute("class", `macro-ring ${ringClass}`)
    ring.setAttribute("cx", "18")
    ring.setAttribute("cy", "18")
    ring.setAttribute("r", "15.9")
    const percent = this.macroPercent(recipe, value)
    ring.setAttribute("stroke-dasharray", `${percent} ${100 - percent}`)
    group.appendChild(ring)
    svg.appendChild(group)

    const text = document.createElementNS("http://www.w3.org/2000/svg", "text")
    text.setAttribute("x", "18")
    text.setAttribute("y", "18")
    text.setAttribute("text-anchor", "middle")
    text.setAttribute("dominant-baseline", "middle")
    text.setAttribute("font-size", "7.5")
    text.setAttribute("font-weight", "700")
    text.setAttribute("fill", textColor)
    text.textContent = `${this.formatNumber(value, 0)}${this.gramsTextValue || "g"}`
    svg.appendChild(text)
    item.appendChild(svg)

    const labelNode = document.createElement("span")
    labelNode.className = "hidden text-xs font-semibold sm:block"
    labelNode.textContent = label
    item.appendChild(labelNode)

    return item
  }

  renderEditorFromField() {
    if (!this.hasEditorTarget || !this.hasFieldTarget) return
    if (this.editorTarget.textContent.trim().length > 0) return
    const value = this.fieldTarget.value.toString()
    if (value.trim().length === 0) return

    this.editorTarget.replaceChildren()
    let lastIndex = 0

    value.replace(this.structuredReferencePattern(), (match, name, id, offset) => {
      this.appendEditorText(value.slice(lastIndex, offset))
      this.editorTarget.appendChild(this.chipElement(this.initialRecipeData(id, name)))
      lastIndex = offset + match.length
    })

    this.appendEditorText(value.slice(lastIndex))
  }

  initialRecipeData(id, name) {
    const recipe = (this.initialRecipesValue || []).find((item) => item.id.toString() === id.toString())

    return {
      id,
      name,
      portion_size_grams: recipe?.portion_size_grams,
      calories_per_portion: recipe?.calories_per_portion,
      proteins_per_portion: recipe?.proteins_per_portion,
      carbs_per_portion: recipe?.carbs_per_portion,
      fats_per_portion: recipe?.fats_per_portion
    }
  }

  chipText(recipe) {
    if (!recipe.portion_size_grams) return recipe.name

    return `${recipe.name} (${this.formatNumber(recipe.portion_size_grams, 2)}${this.gramsTextValue || "g"})`
  }

  appendEditorText(text) {
    if (text.length > 0) {
      this.editorTarget.appendChild(document.createTextNode(text))
    }
  }

  trailingTextFor(range) {
    if (range.endContainer.nodeType !== Node.TEXT_NODE) return ""

    return range.endContainer.textContent.slice(range.endOffset)
  }

  placeCaretAfter(node) {
    const range = document.createRange()
    const selection = window.getSelection()

    range.setStartAfter(node)
    range.collapse(true)
    selection.removeAllRanges()
    selection.addRange(range)
  }

  syncField() {
    if (!this.hasFieldTarget || !this.hasEditorTarget) return

    this.fieldTarget.value = this.serializedValue()
  }

  serializedValue() {
    if (!this.hasEditorTarget) return ""

    return this.serializeNode(this.editorTarget).replace(/\u00a0/g, " ").trim()
  }

  serializeNode(node) {
    if (node.nodeType === Node.TEXT_NODE) return node.textContent
    if (node.nodeType !== Node.ELEMENT_NODE) return ""
    if (node.matches("[data-recipe-id]")) {
      return this.structuredReference({
        id: node.dataset.recipeId,
        name: node.dataset.recipeName
      })
    }
    if (node.tagName === "BR") return "\n"

    return Array.from(node.childNodes).map((child) => this.serializeNode(child)).join("")
  }

  structuredReference(recipe) {
    const name = recipe.name.replace(/[\[\]()]/g, "").trim()
    return `${this.referencePrefix()}${name || recipe.name}${this.referenceMiddle()}${recipe.id}${this.referenceSuffix()}`
  }

  structuredReferencePattern() {
    return new RegExp(
      `${this.escapeRegExp(this.referencePrefix())}([^\\]]+)${this.escapeRegExp(this.referenceMiddle())}(\\d+)${this.escapeRegExp(this.referenceSuffix())}`,
      "g"
    )
  }

  referencePrefix() {
    return this.referencePrefixValue
  }

  referenceMiddle() {
    return this.referenceMiddleValue
  }

  referenceSuffix() {
    return this.referenceSuffixValue
  }

  escapeRegExp(value) {
    return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  }

  scheduleSearch(query) {
    clearTimeout(this.debounceTimeout)

    this.showStatus(this.loadingTextValue)
    this.debounceTimeout = setTimeout(() => this.search(query), SEARCH_DEBOUNCE_MS)
  }

  async search(query) {
    this.abortSearch()
    this.abortController = new AbortController()

    try {
      const url = new URL(this.searchUrlValue, window.location.origin)
      url.searchParams.set("q", query)
      if (query.length === 0) url.searchParams.set("recent", "true")

      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: this.abortController.signal
      })

      if (!response.ok) throw new Error("Recipe search failed")

      this.showResults(await response.json())
    } catch (error) {
      if (error.name === "AbortError") return

      this.recipes = []
      this.selectedIndex = -1
      this.clearList()
      this.showStatus(this.errorTextValue)
    }
  }

  abortSearch() {
    if (this.abortController) {
      this.abortController.abort()
      this.abortController = null
    }
  }

  showResults(recipes) {
    this.recipes = recipes
    this.selectedIndex = recipes.length > 0 ? 0 : -1
    this.clearList()

    if (recipes.length === 0) {
      this.showStatus(this.noResultsTextValue)
      return
    }

    this.hideStatus()
    recipes.forEach((recipe, index) => {
      this.listTarget.appendChild(this.resultElement(recipe, index))
    })
    this.updateSelection()
  }

  resultElement(recipe, index) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "flex w-full items-center gap-3 rounded-md px-3 py-2 text-left text-sm hover:bg-pink-50 focus:bg-pink-50 focus:outline-none"
    button.dataset.action = "mousedown->recipe-mentions#select"
    button.dataset.recipeMentionsIndexParam = index
    button.setAttribute("role", "option")

    if (recipe.thumbnail_url) {
      const image = document.createElement("img")
      image.src = recipe.thumbnail_url
      image.alt = ""
      image.className = "h-10 w-10 flex-none rounded-md object-cover"
      button.appendChild(image)
    }

    const body = document.createElement("span")
    body.className = "min-w-0 flex-1"

    const name = document.createElement("span")
    name.className = "block truncate font-medium text-gray-900"
    name.textContent = recipe.name
    body.appendChild(name)

    const details = document.createElement("span")
    details.className = "mt-0.5 block text-xs text-gray-500"
    details.textContent = this.recipeDetails(recipe)
    body.appendChild(details)

    button.appendChild(body)
    return button
  }

  recipeDetails(recipe) {
    const calories = this.formatNumber(recipe.calories_per_portion, 0)
    const portion = this.formatNumber(recipe.portion_size_grams, 0)

    return `${calories} ${this.kcalTextValue} · ${portion} ${this.gramsTextValue}`
  }

  hasRecipeNutrition(recipe) {
    return [
      recipe.portion_size_grams,
      recipe.calories_per_portion,
      recipe.proteins_per_portion,
      recipe.carbs_per_portion,
      recipe.fats_per_portion
    ].every((value) => value !== undefined && value !== null && value !== "")
  }

  macroPercent(recipe, value) {
    const carbs = Number(recipe.carbs_per_portion || 0)
    const proteins = Number(recipe.proteins_per_portion || 0)
    const fats = Number(recipe.fats_per_portion || 0)
    const total = carbs + proteins + fats

    if (total <= 0) return 0

    return Math.min(Math.round(Number(value || 0) / total * 100), 99)
  }

  formatNumber(value, maximumFractionDigits) {
    return new Intl.NumberFormat(undefined, { maximumFractionDigits }).format(Number(value || 0))
  }

  selectIndex(index) {
    this.selectedIndex = (index + this.recipes.length) % this.recipes.length
    this.updateSelection()
  }

  updateSelection() {
    this.listTarget.querySelectorAll("button").forEach((button, index) => {
      const selected = index === this.selectedIndex
      button.classList.toggle("bg-pink-50", selected)
      button.setAttribute("aria-selected", selected.toString())
    })
  }

  showPanel() {
    if (!this.hasPanelTarget) return

    this.panelTarget.classList.remove("hidden")
    this.editorTarget.setAttribute("aria-expanded", "true")
  }

  hidePanel() {
    if (!this.hasPanelTarget) return

    this.panelTarget.classList.add("hidden")
    this.editorTarget.setAttribute("aria-expanded", "false")
    this.recipes = []
    this.selectedIndex = -1
    this.clearList()
    this.hideStatus()
  }

  isPanelOpen() {
    return this.hasPanelTarget && !this.panelTarget.classList.contains("hidden")
  }

  showStatus(text) {
    if (!this.hasStatusTarget) return

    this.clearList()
    this.statusTarget.textContent = text
    this.statusTarget.classList.remove("hidden")
  }

  hideStatus() {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = ""
    this.statusTarget.classList.add("hidden")
  }

  clearList() {
    if (this.hasListTarget) this.listTarget.replaceChildren()
  }
}
