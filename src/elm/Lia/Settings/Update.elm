module Lia.Settings.Update exposing
    ( Msg(..)
    , Toggle(..)
    , closeSync
    , customizeEvent
    , handle
    , toggle_sound
    , update
    )

import Json.Encode as JE
import Lia.Markdown.Inline.Stringify exposing (stringify)
import Lia.Markdown.Inline.Types exposing (Inlines)
import Lia.Settings.Json as Json
import Lia.Settings.Types exposing (Action(..), Mode(..), Settings)
import Lia.Utils exposing (focus)
import Return exposing (Return)
import Service.Event as Event exposing (Event)
import Service.Settings
import Service.Share
import Service.TTS
import Service.Translate


type Msg
    = Toggle Toggle
    | ChangeTheme String
    | ChangeEditor String
    | ChangeLang String
    | ChangeFontSize Int
    | SwitchMode Mode
    | Reset
    | Handle Event
    | ShareCourse String
    | Ignore


type Toggle
    = TableOfContents
    | Sound
    | Light
    | Sync
    | Action Action
    | SupportMenu
    | TranslateWithGoogle
    | Tooltips


update :
    Maybe { title : String, comment : Inlines }
    -> Msg
    -> Settings
    -> Return Settings Msg sub
update main msg model =
    case msg of
        Handle event ->
            case Event.message event of
                ( "init", settings ) ->
                    settings
                        |> load { model | initialized = True }
                        |> no_log Nothing

                _ ->
                    case event.service of
                        "tts" ->
                            no_log Nothing
                                { model
                                    | speaking =
                                        event
                                            |> Service.TTS.decode
                                            |> (==) Service.TTS.Start
                                }

                        _ ->
                            log Nothing model

        Toggle TableOfContents ->
            log Nothing
                { model
                    | table_of_contents = not model.table_of_contents
                    , action = Nothing
                }

        Toggle SupportMenu ->
            log Nothing
                { model
                    | support_menu = not model.support_menu
                    , action = Nothing
                }

        Toggle Sound ->
            { model | sound = not model.sound }
                |> log Nothing
                |> Return.batchEvent
                    (Event.push "settings" <|
                        if model.sound then
                            Service.TTS.cancel

                        else
                            Service.TTS.repeat
                    )

        Toggle Light ->
            log Nothing { model | light = not model.light }

        Toggle Tooltips ->
            log Nothing { model | tooltips = not model.tooltips }

        Toggle Sync ->
            no_log Nothing { model | sync = not model.sync }

        Toggle (Action action) ->
            no_log
                (case action of
                    ShowModes ->
                        Just "lia-mode-textbook"

                    ShowSettings ->
                        Just "lia-btn-light-mode"

                    _ ->
                        Nothing
                )
                { model
                    | action =
                        if action == Close then
                            Nothing

                        else if model.action /= Just action then
                            Just action

                        else
                            Nothing
                }

        SwitchMode mode ->
            case mode of
                Textbook ->
                    { model | sound = False, mode = Textbook }
                        |> log Nothing
                        |> Return.batchEvent Service.TTS.cancel

                _ ->
                    log Nothing { model | mode = mode }

        ChangeTheme theme ->
            log Nothing
                { model
                    | theme =
                        -- if theme == "custom" && model.customTheme /= Nothing then
                        --    theme
                        --else
                        theme
                }

        ChangeEditor theme ->
            log Nothing { model | editor = theme }

        ChangeFontSize size ->
            log Nothing { model | font_size = size }

        ChangeLang lang ->
            log Nothing { model | lang = lang }

        Reset ->
            model
                |> Return.val
                |> Return.batchEvent Service.Settings.reset

        ShareCourse url ->
            model
                |> Return.val
                |> Return.batchEvent
                    ({ title =
                        main
                            |> Maybe.map .title
                            |> Maybe.withDefault ""
                     , text =
                        main
                            |> Maybe.map (.comment >> stringify)
                            |> Maybe.withDefault ""
                     , url = url
                     }
                        |> Service.Share.link
                    )

        Toggle TranslateWithGoogle ->
            { model | translateWithGoogle = True }
                |> Return.val
                |> Return.batchEvent Service.Translate.google

        Ignore ->
            Return.val model


closeSync : Settings -> Settings
closeSync model =
    { model | sync = False }


handle : Event -> Msg
handle =
    Handle


load : Settings -> JE.Value -> Settings
load model =
    Json.toModel model
        >> Result.withDefault model


toggle_sound : Msg
toggle_sound =
    Toggle Sound


log : Maybe String -> Settings -> Return Settings Msg sub
log elementID settings =
    settings
        |> Return.val
        |> Return.cmd (maybeFocus elementID)
        |> Return.batchEvent (customizeEvent settings)


customizeEvent : Settings -> Event
customizeEvent settings =
    settings
        |> Json.fromModel
        |> Service.Settings.update
            (if settings.theme == "custom" then
                settings.customTheme

             else
                Nothing
            )


no_log : Maybe String -> Settings -> Return Settings Msg sub
no_log elementID =
    Return.val >> Return.cmd (maybeFocus elementID)


maybeFocus : Maybe String -> Cmd Msg
maybeFocus =
    Maybe.map (focus Ignore) >> Maybe.withDefault Cmd.none
