import { LiaStorage } from './storage'
import { SETTINGS, initSettings } from './settings'

class Connector {
  constructor () {
  }

  hasIndex() {
    return false
  }

  connect(send = null) {
    this.send = send
  }

  storage() {
    return new LiaStorage()
  }

  initSettings(data = null, local = false){
    initSettings(this.send, data, local)
  }

  setSettings(data) {
    localStorage.setItem(SETTINGS, JSON.stringify(data))
  }

  getSettings() {
    return JSON.parse(localStorage.getItem(SETTINGS))
  }

  open(uidDB, versionDB, slide) { }

  load(event) { }

  store(event) { }

  update(event, id) { }

  slide(id) { }

  getIndex() { }

  deleteFromIndex(msg) { }

  storeToIndex(json) { }

  restoreFromIndex(uidDB, versionDB = null) { }

  reset(uidDB, versionDB = null) { }

  getFromIndex(uidDB) { }
}

export { Connector }
