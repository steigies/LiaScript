module Lia.Markdown.Code.View exposing (view)

import Array
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events exposing (onClick)
import Html.Keyed as Keyed
import Json.Encode as JE
import Lia.Markdown.Code.Editor as Editor
import Lia.Markdown.Code.Log as Log exposing (Log)
import Lia.Markdown.Code.Terminal as Terminal
import Lia.Markdown.Code.Types exposing (Code(..), File, Snippet, Vector)
import Lia.Markdown.Code.Update exposing (Msg(..))
import Lia.Markdown.HTML.Attributes as Params exposing (Parameters)
import Translations exposing (Lang, codeExecute, codeFirst, codeLast, codeMaximize, codeMinimize, codeNext, codePrev, codeRunning)


view : Lang -> String -> Vector -> Code -> Html Msg
view lang theme model code =
    case code of
        Highlight lang_title_code ->
            lang_title_code
                |> List.map (view_code theme)
                |> Html.div [ Attr.class "lia-code lia-code--block" ]

        Evaluate id_1 ->
            case Array.get id_1 model of
                Just project ->
                    let
                        errors =
                            get_annotations project.log
                    in
                    Html.div [ Attr.class "lia-code lia-code--block" ]
                        [ project.file
                            |> Array.toList
                            |> List.indexedMap (view_eval lang theme project.running errors id_1)
                            |> List.map2 (\a e -> e a) project.attr
                            |> Html.div [ Attr.class "lia-accordion" ]
                        , view_control lang
                            id_1
                            project.version_active
                            (Array.length project.version)
                            project.running
                            (project.terminal /= Nothing)
                        , Html.div [ Attr.class "lia-code-terminal" ]
                            [ view_result project.log
                            , case project.terminal of
                                Nothing ->
                                    Html.text ""

                                Just term ->
                                    term
                                        |> Terminal.view
                                        |> Html.map (UpdateTerminal id_1)
                            ]
                        ]

                Nothing ->
                    Html.text ""


get_annotations : Log -> Int -> JE.Value
get_annotations log file_id =
    log.details
        |> list_get file_id
        |> Maybe.withDefault JE.null


list_get : Int -> List a -> Maybe a
list_get idx list =
    case list of
        [] ->
            Nothing

        x :: xs ->
            if idx == 0 then
                Just x

            else
                list_get (idx - 1) xs


view_code : String -> Snippet -> Html Msg
view_code theme snippet =
    let
        headless =
            snippet.name == ""
    in
    Html.div [ Attr.class "lia-code__input" ]
        [ if headless then
            Html.text ""

          else
            Html.button
                [ Attr.class "lia-accordion-dummy" ]
                [ Html.text snippet.name
                ]
        , highlight theme snippet.attr snippet.lang snippet.code headless
        ]


view_eval : Lang -> String -> Bool -> (Int -> JE.Value) -> Int -> Int -> File -> Parameters -> Html Msg
view_eval lang theme running errors id_1 id_2 file attr =
    let
        headless =
            file.name == ""
    in
    if file.name == "" then
        evaluate theme attr running ( id_1, id_2 ) file headless (errors id_2)

    else
        Html.div (Attr.class "lia-accordion__item" :: Params.toAttribute attr)
            [ Html.div [ Attr.class "lia-accordion__header" ]
                [ Html.h3 [ Attr.class "lia-accordion__headline" ] [ Html.text file.name ]
                , Html.button
                    [ Attr.class "lia-accordion__toggle lia-btn lia-btn--transparent"
                    , Attr.class <|
                        "icon"
                            ++ (if file.visible then
                                    " icon-minus"

                                else
                                    " icon-plus"
                               )
                    , onClick <| FlipView id_1 id_2
                    ]
                    []
                ]
            , Html.div
                [ Attr.classList
                    [ ( "lia-accordion__content", True )
                    , ( "active", file.visible )
                    ]
                ]
                [ Html.div [ Attr.class "lia-code__input" ]
                    [ if file.visible then
                        Html.button
                            [ Attr.class "lia-btn lia-btn--transparent lia-code__min-max"
                            , Attr.class <|
                                if file.fullscreen then
                                    "icon icon-chevron-up"

                                else
                                    "icon icon-chevron-down"
                            , onClick <| FlipFullscreen id_1 id_2
                            , Attr.title <|
                                if file.fullscreen then
                                    codeMinimize lang

                                else
                                    codeMaximize lang
                            ]
                            []

                      else
                        Html.text ""
                    , evaluate theme attr running ( id_1, id_2 ) file headless (errors id_2)
                    ]
                ]
            ]


toStyle : Bool -> Bool -> Int -> List (Html.Attribute msg)
toStyle visible headless pix =
    let
        top_border =
            if headless then
                "4px"

            else
                "0px"
    in
    [ Attr.style "max-height"
        (if visible then
            String.fromInt pix ++ "px"

         else
            "0px"
        )
    , Attr.style "transition" "max-height 0.25s ease-out"
    , Attr.style "border-top-left-radius" top_border
    , Attr.style "border-top-right-radius" top_border
    ]


lines : String -> Int
lines code =
    code
        |> String.lines
        |> List.length


pixel : Int -> Int
pixel from_lines =
    from_lines * 21 + 16


highlight : String -> Parameters -> String -> String -> Bool -> Html Msg
highlight theme attr lang code headless =
    let
        top_border =
            if headless then
                "4px"

            else
                "0px"

        readOnly =
            if Params.get "data-readonly" attr == Nothing then
                True

            else
                Params.isSet "data-readonly" attr
    in
    Editor.editor
        (attr
            |> Params.toAttribute
            |> List.append
                [ Attr.style "border-top-left-radius" top_border
                , Attr.style "border-top-right-radius" top_border
                , Editor.value code
                , Editor.mode lang
                , attr
                    |> Params.get "data-theme"
                    |> Maybe.withDefault theme
                    |> Editor.theme
                , attr
                    |> Params.get "data-tabsize"
                    |> Maybe.andThen String.toInt
                    |> Maybe.withDefault 2
                    |> Editor.tabSize
                , attr
                    |> Params.get "data-marker"
                    |> Maybe.withDefault ""
                    |> Editor.marker
                , attr
                    |> Params.get "data-firstlinenumber"
                    |> Maybe.andThen String.toInt
                    |> Maybe.withDefault 1
                    |> Editor.firstLineNumber
                , Editor.useSoftTabs False
                , Editor.readOnly readOnly
                , Editor.showCursor (not readOnly)
                , Editor.highlightActiveLine False
                , attr
                    |> Params.isSet "data-showgutter"
                    |> Editor.showGutter
                , Editor.showPrintMargin False
                , attr
                    |> Params.get "data-fontsize"
                    |> Maybe.withDefault "12pt"
                    |> Editor.fontSize
                ]
        )
        []


evaluate : String -> Parameters -> Bool -> ( Int, Int ) -> File -> Bool -> JE.Value -> Html Msg
evaluate theme attr running ( id_1, id_2 ) file headless errors =
    let
        total_lines =
            lines file.code

        max_lines =
            if file.fullscreen then
                total_lines

            else if total_lines > 16 then
                16

            else
                total_lines

        readOnly =
            if running then
                running

            else
                attr
                    |> Params.isSet "data-readonly"
    in
    Editor.editor
        (attr
            |> Params.toAttribute
            |> List.append
                (max_lines
                    |> pixel
                    |> toStyle file.visible headless
                )
            |> List.append
                [ Editor.onChange <| Update id_1 id_2
                , Editor.value file.code
                , Editor.mode file.lang
                , attr
                    |> Params.get "data-theme"
                    |> Maybe.withDefault theme
                    |> Editor.theme
                , Editor.maxLines
                    (if max_lines > 16 then
                        -1

                     else
                        max_lines
                    )
                , Editor.readOnly readOnly
                , attr
                    |> Params.get "data-tabsize"
                    |> Maybe.andThen String.toInt
                    |> Maybe.withDefault 2
                    |> Editor.tabSize
                , attr
                    |> Params.get "data-fontsize"
                    |> Maybe.withDefault "12pt"
                    |> Editor.fontSize
                , attr
                    |> Params.get "data-marker"
                    |> Maybe.withDefault ""
                    |> Editor.marker
                , attr
                    |> Params.get "data-firstlinenumber"
                    |> Maybe.andThen String.toInt
                    |> Maybe.withDefault 1
                    |> Editor.firstLineNumber
                , if Params.get "data-showgutter" attr /= Nothing then
                    attr
                        |> Params.isSet "data-showgutter"
                        |> Editor.showGutter

                  else
                    Editor.showGutter True
                , Editor.useSoftTabs False
                , Editor.annotations errors
                , Editor.enableBasicAutocompletion True
                , Editor.enableLiveAutocompletion True
                , Editor.enableSnippets True
                , Editor.extensions [ "language_tools" ]
                ]
        )
        []


view_result : Log -> Html msg
view_result log =
    if Array.isEmpty log.messages then
        Html.text ""

    else
        Log.view log
            |> Keyed.node "pre"
                [ Attr.class "lia-code-terminal__output"
                , log.messages
                    |> Log.length
                    |> (*) 2
                    |> scroll_to_end
                ]


scroll_to_end : Int -> Html.Attribute msg
scroll_to_end lines_ =
    lines_
        |> (*) 14
        |> (+) 14
        |> String.fromInt
        |> JE.string
        |> Attr.property "scrollTop"


view_control : Lang -> Int -> Int -> Int -> Bool -> Bool -> Html Msg
view_control lang idx version_active version_count running terminal =
    let
        forward =
            running || (version_active == 0)

        backward =
            running || (version_active == (version_count - 1))
    in
    Html.div [ Attr.class "lia-code-control" ]
        [ Html.div [ Attr.class "lia-code-control__action" ]
            [ case ( running, terminal ) of
                ( True, False ) ->
                    Html.button
                        [ Attr.class "lia-btn lia-btn--transparent is-disabled icon icon-refresh rotating"
                        , Attr.title (codeRunning lang)
                        , Attr.disabled True
                        ]
                        []

                ( True, True ) ->
                    Html.button
                        [ Attr.class "lia-btn lia-btn--transparent icon icon-stop-circle"
                        , Attr.title (codeRunning lang)
                        , onClick (Stop idx)
                        ]
                        []

                _ ->
                    Html.button
                        [ Attr.class "lia-btn lia-btn--transparent icon icon-compile-circle"
                        , onClick (Eval idx)
                        , Attr.title (codeExecute lang)
                        ]
                        []
            ]
        , Html.div [ Attr.class "lia-code-control__version" ]
            [ Html.button
                [ First idx |> onClick
                , Attr.class "lia-btn lia-btn--transparent icon icon-end-left"
                , Attr.title (codeFirst lang)
                , Attr.disabled forward
                ]
                []
            , Html.button
                [ (version_active - 1) |> Load idx |> onClick
                , Attr.class "lia-btn lia-btn--transparent icon icon-chevron-left"
                , Attr.title (codePrev lang)
                , Attr.disabled forward
                ]
                []
            , Html.span
                [ Attr.class "lia-label"
                ]
                [ Html.text (String.fromInt version_active) ]
            , Html.button
                [ (version_active + 1) |> Load idx |> onClick
                , Attr.class "lia-btn lia-btn--transparent icon icon-chevron-right"
                , Attr.title (codeNext lang)
                , Attr.disabled backward
                ]
                []
            , Html.button
                [ Last idx |> onClick
                , Attr.class "lia-btn lia-btn--transparent icon icon-end-right"
                , Attr.title (codeLast lang)
                , Attr.disabled backward
                ]
                []
            ]
        ]
