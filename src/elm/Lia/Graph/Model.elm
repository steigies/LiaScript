module Lia.Graph.Model exposing
    ( Edge
    , Graph
    , Node(..)
    , addCourse
    , addEdge
    , addHashtag
    , addLink
    , addNode
    , addSection
    , init
    , parseSections
    , section
    )

import Array
import Browser.Events exposing (Visibility(..))
import Dict exposing (Dict)
import Html exposing (node)
import Lia.Markdown.Inline.Stringify exposing (stringify)
import Lia.Markdown.Inline.Types exposing (Inline(..))
import Lia.Section exposing (Section)


type Node
    = Hashtag
        { name : String
        , visible : Bool
        }
    | Section
        { id : Int
        , indentation : Int
        , weight : Int
        , name : String
        , visible : Bool
        }
    | Link
        { name : String
        , url : String
        , visible : Bool
        }
    | Course
        { name : String
        , url : String
        , visible : Bool
        }


type alias Edge =
    { from : String
    , to : String
    }


type alias Graph =
    { root : Maybe Node
    , node : Dict String Node
    , edge : List Edge
    }


init : Graph
init =
    Graph
        Nothing
        Dict.empty
        []


addNode : Node -> Graph -> Graph
addNode node graph =
    { graph | node = Dict.insert (nodeID node) node graph.node }


addEdge : Node -> Node -> Graph -> Graph
addEdge from to graph =
    let
        edge =
            Edge (nodeID from) (nodeID to)
    in
    if List.member edge graph.edge then
        graph

    else
        { graph
            | edge = Edge (nodeID from) (nodeID to) :: graph.edge
        }


nodeID : Node -> String
nodeID node =
    case node of
        Course lia ->
            "lia: " ++ lia.url

        Hashtag tag ->
            "tag: " ++ String.toLower tag.name

        Link link ->
            "url: " ++ link.url

        Section sec ->
            "sec: " ++ String.fromInt sec.id


addHashtag : String -> Graph -> Graph
addHashtag name =
    rootConnect (Hashtag { name = name, visible = True })


addLink : { name : String, url : String } -> Graph -> Graph
addLink link =
    rootConnect (Link { name = link.name, url = link.url, visible = True })


section : Int -> Node
section id =
    Section
        { id = id
        , indentation = -1
        , weight = -1
        , name = ""
        , visible = False
        }


addSection : Int -> Graph -> Graph
addSection id graph =
    case graph.root of
        Just root ->
            addEdge
                root
                (section id)
                graph

        _ ->
            graph


addCourse : { name : String, url : String } -> Graph -> Graph
addCourse lia =
    rootConnect (Course { name = lia.name, url = lia.url, visible = True })


rootConnect : Node -> Graph -> Graph
rootConnect node graph =
    case graph.root of
        Just root ->
            graph
                |> addNode node
                |> addEdge root node

        Nothing ->
            addNode node graph


parseSections sections =
    parseSectionsHelper [] (Array.toList sections)


parseSectionsHelper prev sections graph =
    case ( sections, prev ) of
        ( [], _ ) ->
            graph

        ( x :: xs, [] ) ->
            graph
                |> addNode
                    (Section
                        { id = x.id
                        , weight = String.length x.code
                        , indentation = x.indentation
                        , name = stringify x.title
                        , visible = True
                        }
                    )
                |> parseSectionsHelper [ x ] xs

        ( x :: xs, p :: ps ) ->
            if x.indentation > p.indentation then
                graph
                    |> addNode
                        (Section
                            { id = x.id
                            , weight = String.length x.code
                            , indentation = x.indentation
                            , name = stringify x.title
                            , visible = True
                            }
                        )
                    |> addEdge (section p.id) (section x.id)
                    |> parseSectionsHelper (x :: prev) xs

            else
                parseSectionsHelper ps sections graph
