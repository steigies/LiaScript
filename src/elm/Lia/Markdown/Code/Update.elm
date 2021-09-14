module Lia.Markdown.Code.Update exposing
    ( Msg(..)
    , handle
    , update
    )

import Array exposing (Array)
import Conditional.Array as CArray
import Json.Decode as JD
import Json.Encode as JE
import Lia.Markdown.Code.Events as Event
import Lia.Markdown.Code.Json as Json
import Lia.Markdown.Code.Log as Log
import Lia.Markdown.Code.Terminal as Terminal
import Lia.Markdown.Code.Types exposing (Code(..), File, Model, Project, loadVersion, updateVersion)
import Lia.Markdown.Effect.Script.Types exposing (Scripts)
import Port.Eval exposing (Eval, event)
import Port.Event as PEvent exposing (Event)
import Return exposing (Return)


type Msg
    = Eval Int
    | Stop Int
    | Update Int Int String
    | FlipView Code Int
    | FlipFullscreen Code Int
    | Load Int Int
    | First Int
    | Last Int
    | UpdateTerminal Int Terminal.Msg
    | Handle Event
    | Resize Code String


handle : Event -> Msg
handle =
    Handle


restore : JE.Value -> Model -> Return Model msg sub
restore json model =
    case
        model.evaluate
            |> Array.map .attr
            |> Array.toList
            |> Json.toVector json
    of
        Ok (Just vector) ->
            Json.merge model vector
                |> Return.val

        Ok Nothing ->
            model
                |> Return.val
                |> Return.batchEvents
                    (if Array.length model.evaluate == 0 then
                        []

                     else
                        [ Event.store model.evaluate ]
                    )

        Err _ ->
            model
                |> Return.val


update : Scripts a -> Msg -> Model -> Return Model msg sub
update scripts msg model =
    case msg of
        Eval idx ->
            execute scripts model idx
                |> Return.sync (Event "eval" idx JE.null)

        Update id_1 id_2 code_str ->
            update_file
                id_1
                id_2
                model
                (\f -> { f | code = code_str })
                (\_ -> [])
                |> Return.sync
                    ([ ( "id", JE.int id_2 )
                     , ( "code", JE.string code_str )
                     ]
                        |> JE.object
                        |> Event "update" id_1
                    )

        FlipView (Evaluate id_1) id_2 ->
            flipEval model id_1 id_2
                |> Return.sync (Event "flip_eval" id_1 (JE.int id_2))

        FlipView (Highlight id_1) id_2 ->
            flipHigh model id_1 id_2
                |> Return.sync (Event "flip_high" id_1 (JE.int id_2))

        FlipFullscreen (Highlight id_1) id_2 ->
            { model
                | highlight =
                    CArray.setWhen id_1
                        (model.highlight
                            |> Array.get id_1
                            |> Maybe.map
                                (\pro ->
                                    { pro
                                        | file =
                                            updateArray (\f -> { f | fullscreen = not f.fullscreen }) id_2 pro.file
                                    }
                                )
                        )
                        model.highlight
            }
                |> Return.val

        FlipFullscreen (Evaluate id_1) id_2 ->
            update_file
                id_1
                id_2
                model
                (\f -> { f | fullscreen = not f.fullscreen })
                (Event.fullscreen id_1 id_2)

        Load idx version ->
            load model idx version
                |> Return.sync (Event "load" idx (JE.int version))

        First idx ->
            load model idx 0
                |> Return.sync (Event "load" idx (JE.int 0))

        Last idx ->
            let
                version =
                    model
                        |> maybe_project idx (.version >> Array.length >> (+) -1)
                        |> Maybe.map .value
                        |> Maybe.withDefault 0
            in
            load model idx version
                |> Return.sync (Event "load" idx (JE.int version))

        Handle event ->
            case Port.Event.destructure event of
                ( Just ( "eval", Just section ), message ) ->
                    let
                        e =
                            Event.evalDecode event
                    in
                    case e.result of
                        "LIA: wait" ->
                            model
                                |> maybe_project section (\p -> { p | log = Log.empty })
                                |> maybe_update section model

                        "LIA: stop" ->
                            model
                                |> maybe_project section stop
                                |> Maybe.map (Event.version_update section)
                                |> maybe_update section model

                        "LIA: clear" ->
                            model
                                |> maybe_project section clr
                                |> maybe_update section model

                        -- preserve previous logging by setting ok to false
                        "LIA: terminal" ->
                            model
                                |> maybe_project section (\p -> { p | terminal = Just <| Terminal.init })
                                |> maybe_update section model

                        _ ->
                            model
                                |> maybe_project section (set_result False e)
                                |> Maybe.map (Event.version_update section)
                                |> maybe_update section model

                ( Just ( "restore", _ ), message ) ->
                    restore message model

                ( Just ( "debug", Just section ), message ) ->
                    model
                        |> maybe_project section (logger Log.add Log.Debug message)
                        |> maybe_update section model

                ( Just ( "info", Just section ), message ) ->
                    model
                        |> maybe_project section (logger Log.add Log.Info message)
                        |> maybe_update section model

                ( Just ( "warn", Just section ), message ) ->
                    model
                        |> maybe_project section (logger Log.add Log.Warn message)
                        |> maybe_update section model

                ( Just ( "error", Just section ), message ) ->
                    model
                        |> maybe_project section (logger Log.add Log.Error message)
                        |> maybe_update section model

                ( Just ( "html", Just section ), message ) ->
                    model
                        |> maybe_project section (logger Log.add Log.HTML message)
                        |> maybe_update section model

                ( Just ( "stream", Just section ), message ) ->
                    model
                        |> maybe_project section (logger Log.add Log.Stream message)
                        |> maybe_update section model

                "sync" ->
                    case PEvent.decode event.message of
                        Ok e ->
                            case e.topic of
                                "flip_eval" ->
                                    e.message
                                        |> JD.decodeValue JD.int
                                        |> Result.map (flipEval model e.section)
                                        |> Result.withDefault (Return.val model)

                                "flip_high" ->
                                    e.message
                                        |> JD.decodeValue JD.int
                                        |> Result.map (flipHigh model e.section)
                                        |> Result.withDefault (Return.val model)

                                "eval" ->
                                    execute scripts model e.section

                                "update" ->
                                    case
                                        JD.decodeValue
                                            (JD.map2 Tuple.pair
                                                (JD.field "id" JD.int)
                                                (JD.field "code" JD.string)
                                            )
                                            e.message
                                    of
                                        Ok ( id, code ) ->
                                            update_file
                                                e.section
                                                id
                                                model
                                                (\f -> { f | code = code })
                                                (\_ -> [])

                                        _ ->
                                            Return.val model

                                "load" ->
                                    e.message
                                        |> JD.decodeValue JD.int
                                        |> Result.map (load model e.section)
                                        |> Result.withDefault (Return.val model)

                                _ ->
                                    Return.val model

                        _ ->
                            Return.val model

                _ ->
                    Return.val model

        Stop idx ->
            model
                |> maybe_project idx (\p -> { p | running = False, terminal = Nothing })
                |> Maybe.map (Return.batchEvent (Event.stop idx))
                |> maybe_update idx model

        Resize code height ->
            Return.val <|
                case code of
                    Evaluate id ->
                        { model | evaluate = onResize id height model.evaluate }

                    Highlight id ->
                        { model | highlight = onResize id height model.highlight }

        UpdateTerminal idx childMsg ->
            model
                |> maybe_project idx (update_terminal (Event.input idx) childMsg)
                |> Maybe.map .value
                |> maybe_update idx model


onResize : Int -> String -> Array Project -> Array Project
onResize id height code =
    CArray.setWhen id
        (code
            |> Array.get id
            |> Maybe.map (\pro -> { pro | logSize = Just height })
        )
        code


update_terminal : (String -> Event) -> Terminal.Msg -> Project -> Return Project msg sub
update_terminal f msg project =
    case project.terminal |> Maybe.map (Terminal.update msg) of
        Just ( terminal, Nothing ) ->
            { project | terminal = Just terminal }
                |> Return.val

        Just ( terminal, Just str ) ->
            { project | terminal = Just terminal, log = Log.add Log.Info str project.log }
                |> Return.val
                |> Return.batchEvent (f str)

        Nothing ->
            Return.val project


eval : Scripts a -> Int -> Project -> Return Project msg sub
eval scripts idx project =
    { project | running = True }
        |> Return.val
        |> Return.batchEvent (Event.eval scripts idx project)


maybe_project : Int -> (Project -> x) -> Model -> Maybe (Return x cmd sub)
maybe_project idx f =
    .evaluate
        >> Array.get idx
        >> Maybe.map (f >> Return.val)


maybe_update : Int -> Model -> Maybe (Return Project msg sub) -> Return Model msg sub
maybe_update idx model =
    Maybe.map (Return.mapVal (\v -> { model | evaluate = Array.set idx v model.evaluate }))
        >> Maybe.withDefault (Return.val model)


update_file : Int -> Int -> Model -> (File -> File) -> (File -> List Event) -> Return Model msg sub
update_file id_1 id_2 model f f_log =
    case Array.get id_1 model.evaluate of
        Just project ->
            case project.file |> Array.get id_2 |> Maybe.map f of
                Just file ->
                    { model
                        | evaluate =
                            Array.set id_1
                                { project
                                    | file = Array.set id_2 file project.file
                                }
                                model.evaluate
                    }
                        |> Return.val
                        |> Return.batchEvents (f_log file)

                Nothing ->
                    Return.val model

        Nothing ->
            Return.val model


is_version_new : Int -> Return Project msg sub -> Return Project msg sub
is_version_new idx return =
    case updateVersion return.value of
        Just ( new_project, repo_update ) ->
            new_project
                |> Return.replace return
                |> Return.batchEvent (Event.version_append idx new_project repo_update)

        Nothing ->
            return


stop : Project -> Project
stop project =
    case project.version |> Array.get project.version_active of
        Just ( code, _ ) ->
            { project
                | version =
                    Array.set
                        project.version_active
                        ( code, project.log )
                        project.version
                , running = False
                , terminal = Nothing
            }

        Nothing ->
            project


set_result : Bool -> Eval -> Project -> Project
set_result continue e project =
    case project.version |> Array.get project.version_active of
        Just ( code, _ ) ->
            { project
                | version =
                    Array.set
                        project.version_active
                        ( code, Log.add_Eval e project.log )
                        project.version
                , running =
                    if continue then
                        project.running

                    else
                        False
                , log =
                    Log.add_Eval e project.log
            }

        Nothing ->
            project


clr : Project -> Project
clr project =
    case project.version |> Array.get project.version_active of
        Just ( code, _ ) ->
            { project
                | version =
                    Array.set
                        project.version_active
                        ( code, Log.empty )
                        project.version
                , log = Log.empty
            }

        Nothing ->
            project


logger : (Log.Level -> String -> Log.Log -> Log.Log) -> Log.Level -> JD.Value -> Project -> Project
logger fn level event_str project =
    case ( project.version |> Array.get project.version_active, JD.decodeValue JD.string event_str ) of
        ( Just ( code, _ ), Ok str ) ->
            { project
                | version =
                    Array.set
                        project.version_active
                        ( code, fn level str project.log )
                        project.version
                , log = fn level str project.log
            }

        _ ->
            project


updateArray : (e -> e) -> Int -> Array e -> Array e
updateArray fn i array =
    CArray.setWhen i
        (array
            |> Array.get i
            |> Maybe.map fn
        )
        array


flipEval : Model -> Int -> Int -> Return Model msg sub
flipEval model id_1 id_2 =
    update_file
        id_1
        id_2
        model
        (\f -> { f | visible = not f.visible })
        (Event.flip_view id_1 id_2)


flipHigh : Model -> Int -> Int -> Return Model msg sub
flipHigh model id_1 id_2 =
    { model
        | highlight =
            CArray.setWhen id_1
                (model.highlight
                    |> Array.get id_1
                    |> Maybe.map
                        (\pro ->
                            { pro
                                | file =
                                    updateArray (\f -> { f | visible = not f.visible }) id_2 pro.file
                            }
                        )
                )
                model.highlight
    }
        |> Return.val


execute : Scripts a -> Model -> Int -> Return Model msg sub
execute scripts model id =
    model
        |> maybe_project id (eval scripts id)
        |> Maybe.map (.value >> is_version_new id)
        |> maybe_update id model


load : Model -> Int -> Int -> Return Model msg sub
load model id version =
    model
        |> maybe_project id (loadVersion version)
        |> Maybe.map (Event.load id)
        |> maybe_update id model
