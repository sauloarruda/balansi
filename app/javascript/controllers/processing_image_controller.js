import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    src: String,
    interval: Number
  }

  connect() {
    this.scheduleReload()
  }

  disconnect() {
    this.clearTimer()
  }

  reload() {
    if (!this.hasSrcValue) return

    const image = new Image()

    image.onload = () => {
      this.element.src = image.src
      this.clearTimer()
    }

    image.onerror = () => {
      this.scheduleReload()
    }

    image.src = this.reloadSrc()
  }

  scheduleReload() {
    this.clearTimer()
    this.timer = setTimeout(() => this.reload(), this.reloadInterval)
  }

  clearTimer() {
    if (!this.timer) return

    clearTimeout(this.timer)
    this.timer = null
  }

  reloadSrc() {
    const url = new URL(this.srcValue, window.location.origin)
    url.searchParams.set("processing_image_retry", Date.now().toString())

    return url.toString()
  }

  get reloadInterval() {
    return this.hasIntervalValue ? this.intervalValue : 3_000
  }
}
