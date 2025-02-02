module Lia.Definition.Types exposing
    ( Definition
    , Resource(..)
    , addToResources
    , add_imports
    , add_macros
    , add_translation
    , default
    , getIcon
    , get_translations
    , setPersistent
    )

import Const
import Dict exposing (Dict)
import Lia.Markdown.HTML.Attributes exposing (toURL)
import Lia.Markdown.Inline.Types exposing (Inlines)
import Lia.Parser.PatReplace exposing (link)
import Lia.Settings.Types exposing (Mode)


type Resource
    = Link String
    | Script String


type alias Definition =
    { author : String
    , date : String
    , email : String
    , language : String
    , logo : String
    , narrator : String
    , version : String
    , comment : Inlines
    , resources : List Resource
    , base : String
    , translation : Dict String String
    , macro : Dict String String
    , imports : List String
    , attributes : List Inlines
    , section : Int
    , uid : Int
    , debug : Bool
    , onload : String
    , lightMode : Maybe Bool
    , mode : Maybe Mode
    }


default : String -> Definition
default base =
    { author = ""
    , date = ""
    , email = ""
    , language = "en"
    , logo = ""
    , narrator = "US English Male"
    , version = "0.0.1"
    , comment = []
    , resources = []
    , base = base
    , translation = Dict.empty
    , macro = Dict.empty
    , imports = []
    , attributes = []
    , section = -1
    , uid = -1
    , debug = False
    , onload = ""
    , lightMode = Nothing
    , mode = Nothing
    }


add_translation : String -> Definition -> Definition
add_translation str def =
    case String.words str of
        [ lang, url ] ->
            { def
                | translation =
                    Dict.insert lang (toURL def.base url) def.translation
            }

        _ ->
            def


get_translations : Definition -> List ( String, String )
get_translations def =
    Dict.toList def.translation


add_macros : Definition -> Definition -> Definition
add_macros orig temp =
    { orig
        | macro = Dict.union orig.macro temp.macro
        , attributes = List.append orig.attributes temp.attributes
        , onload =
            String.trim
                (orig.onload
                    ++ (if orig.onload /= temp.onload then
                            "\n" ++ temp.onload

                        else
                            ""
                       )
                )
        , resources = List.append orig.resources temp.resources
    }


add_imports : String -> Definition -> Definition
add_imports url def =
    { def | imports = append link def.base url def.imports }


addToResources : (String -> Resource) -> String -> Definition -> Definition
addToResources to urls def =
    { def | resources = append to def.base urls def.resources }


append : (String -> a) -> String -> String -> List a -> List a
append to base urls list =
    urls
        |> String.words
        |> List.map (toURL base >> to)
        |> List.append list


getIcon : Definition -> String
getIcon =
    .macro
        >> Dict.get "icon"
        >> Maybe.withDefault Const.icon


setPersistent : Bool -> Definition -> Definition
setPersistent b def =
    { def
        | macro =
            Dict.insert "persistent"
                (if b then
                    "true"

                 else
                    "false"
                )
                def.macro
    }
