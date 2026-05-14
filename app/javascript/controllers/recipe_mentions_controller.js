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
    chip.dataset.recipeId = recipe.id
    chip.dataset.recipeName = recipe.name
    if (recipe.portion_size_grams) chip.dataset.recipePortionSizeGrams = recipe.portion_size_grams
    chip.className = "recipe-mention-chip"
    chip.textContent = this.chipText(recipe)

    return chip
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
      portion_size_grams: recipe?.portion_size_grams
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
    return `@[${name || recipe.name}](recipe:${recipe.id})`
  }

  structuredReferencePattern() {
    return /@\[([^\]]+)\]\(recipe:(\d+)\)/g
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
