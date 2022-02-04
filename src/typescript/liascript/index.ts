// @ts-ignore
import { Elm } from '../../elm/Main.elm'

import log from './log'

import './types/globals'
import Lia from './types/lia.d'
import Port from './types/ports'
import { Connector } from '../connectors/Base/index'

import { initTooltip } from '../webcomponents/tooltip/index'

// Services
import Console from './service/Console'
import Database from './service/Database'
import { Service as Resource } from './service/Resource'
import Script from './service/Script'
import Share from './service/Share'
import Slide from './service/Slide'
import Swipe from './service/Swipe'
import Sync from './service/Sync'
import TTS from './service/TTS'
import Translate from './service/Translate'
import { LiaStorage } from '../connectors/Base/storage'

// ----------------------------------------------------------------------------
// GLOBAL INITIALIZATION

// TODO: CHECK window.LIA.defaultCourse functionality

if (!window.LIA) {
  window.LIA = {
    eventSemaphore: 0,
    send: (_event: Lia.Event) => {
      console.warn('send not defined')
    },
    img: {
      load: function (_url: string, _width: number, _height: number) {
        console.warn('img.load not defined')
      },
      click: function (_url: string) {
        console.warn('img.click not defined')
      },
      zoom: function (e: MouseEvent | TouchEvent) {
        const target = e.target as HTMLImageElement

        if (target) {
          const zooming = e.currentTarget as HTMLImageElement

          if (zooming) {
            if (target.width < target.naturalWidth) {
              var offsetX =
                e instanceof MouseEvent ? e.offsetX : e.touches[0].pageX
              var offsetY =
                e instanceof MouseEvent ? e.offsetY : e.touches[0].pageY
              var x = (offsetX / zooming.offsetWidth) * 100
              var y = (offsetY / zooming.offsetHeight) * 100
              zooming.style.backgroundPosition = x + '% ' + y + '%'
              zooming.style.cursor = 'zoom-in'
            } else {
              zooming.style.cursor = ''
            }
          }
        }
      },
    },
    playback: function (_event: Lia.Event) {
      console.warn('playback not defined')
    },
    showFootnote: function (key: string) {
      console.warn('showFootnote not defined')
    },
  }
}

if (window.LIA.debug === undefined) {
  window.LIA.debug = false
}

var liaStorage = null

// ----------------------------------------------------------------------------
class LiaScript {
  private app: any
  public connector: Connector
  public sync?: any

  constructor(
    elem: HTMLElement,
    connector: Connector,
    allowSync: boolean = false,
    debug: boolean = false,
    courseUrl: string | null = null,
    script: string | null = null
  ) {
    window.LIA.debug = debug

    this.app = Elm.Main.init({
      //node: elem,
      flags: {
        courseUrl: window.LIA.defaultCourseURL || courseUrl,
        script: script,
        settings: connector.getSettings(),
        screen: {
          width: window.innerWidth,
          height: window.innerHeight,
        },
        hasShareAPI: Share.isSupported(),
        hasIndex: connector.hasIndex(),
        syncSupport: Sync.supported(allowSync),
      },
    })

    const sendTo = this.app.ports.event2elm.send

    const sender = function (msg: Lia.Event) {
      if (msg.reply) {
        if (window.LIA.debug) {
          log.info(`LIA <<< (${msg.track}) :`, msg.message)
        }
        sendTo(msg)
      }
    }

    window.LIA.send = sender

    this.connector = connector

    this.initEventSystem(elem, this.app.ports.event2js.subscribe, sender)

    liaStorage = this.connector.storage()

    let self = this

    window.LIA.img.load = (src: string, width: number, height: number) => {
      self.app.ports.media.send([src, width, height])
    }
    window.LIA.img.click = (url: string) => {
      // abuse media port to open modals
      if (document.getElementsByClassName('lia-modal').length === 0) {
        self.app.ports.media.send([url, null, null])
      }
    }
    window.LIA.showFootnote = (key: string) => {
      self.app.ports.footnote.send(key)
    }

    // Attach a tooltip-div to the end of the DOM
    initTooltip()
  }

  reset() {
    this.app.ports.event2elm.send({
      track: [
        {
          topic: Port.RESET,
          id: null,
        },
      ],
      message: null,
    })
  }

  initEventSystem(
    elem: HTMLElement,
    jsSubscribe: (fn: (_: Lia.Event) => void) => void,
    elmSend: Lia.Send
  ) {
    log.info('initEventSystem')

    Database.init(elmSend, this.connector)
    TTS.init(elmSend)
    Script.init(elmSend)
    Swipe.init(elem, elmSend)
    Translate.init(elmSend)
    Sync.init(elmSend)

    let connector = this.connector
    jsSubscribe((event: Lia.Event) => {
      if (window.LIA.debug)
        log.info(
          `LIA >>> (${JSON.stringify(event.track)})`,
          event.service,
          event.message
        )

      switch (event.service) {
        case Database.PORT:
          Database.handle(event)
          break

        case Slide.PORT:
          if (event.message.param.slide) {
            // store the current slide number within the backend
            connector.slide(event.message.param.slide)
          }
          Slide.handle(event)
          break

        case TTS.PORT:
          TTS.handle(event)
          break

        case Script.PORT:
          Script.handle(event)
          break

        case Console.PORT:
          Console.handle(event)
          break

        case Sync.PORT:
          Sync.handle(event)
          break

        case Share.PORT:
          Share.handle(event)
          break

        case Resource.PORT:
          Resource.handle(event)
          break

        case Translate.PORT:
          Translate.handle(event)
          break

        default:
          console.warn('Unknown Service => ', event)
      }
    })
  }
}

/*else
    switch (event.track[0][0]) {

      case Port.PERSISTENT: {
        if (event.message === 'store') {
          // todo, needs to be moved back
          // persistent.store(event.section)
          elmSend({
            reply: true,
            track: [[Port.LOAD, -1]],
            service: null,
            message: null,
          })
        }

        break
      }

      case Port.RESET: {
        self.connector.reset()
        window.location.reload()
        break
      }
    }
    */

export default LiaScript
