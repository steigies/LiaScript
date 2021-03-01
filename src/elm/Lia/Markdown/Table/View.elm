module Lia.Markdown.Table.View exposing (view)

import Array
import Const
import Dict
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events exposing (onClick)
import Html.Lazy as Lazy
import Lia.Markdown.Chart.Types exposing (Diagram(..), Labels, Point)
import Lia.Markdown.Chart.View as Chart
import Lia.Markdown.Config exposing (Config)
import Lia.Markdown.Effect.Script.Types exposing (Scripts)
import Lia.Markdown.HTML.Attributes as Param exposing (Parameters)
import Lia.Markdown.Inline.Types exposing (Inlines)
import Lia.Markdown.Table.Matrix as Matrix exposing (Matrix, Row)
import Lia.Markdown.Table.Types
    exposing
        ( Cell
        , Class(..)
        , State
        , Table
        , Vector
        , isEmpty
        , isNumber
        , toCell
        , toMatrix
        )
import Lia.Markdown.Table.Update as Sub
import Lia.Markdown.Update exposing (Msg(..))
import Lia.Utils exposing (blockKeydown)
import Set
import Translations exposing (Lang)


view : Config sub -> Parameters -> Table -> Html Msg
view config attr table =
    let
        state =
            getState table.id config.section.table_vector
    in
    if diagramShow attr state.diagram then
        Lazy.lazy8 viewDiagram
            config.main.lang
            table
            state
            config.main.scripts
            config.main.visible
            config.screen.width
            config.light
            attr

    else if table.head == [] && table.format == [] then
        state
            |> unformatted config.view (toMatrix config.main.scripts config.main.visible table.body) table.id
            |> toTable config.main.lang table.id attr table.class

    else
        state
            |> formatted config.view table.head table.format (toMatrix config.main.scripts config.main.visible table.body) table.id
            |> toTable config.main.lang table.id attr table.class


viewDiagram : Lang -> Table -> State -> Scripts a -> Maybe Int -> Int -> Bool -> Parameters -> Html Msg
viewDiagram lang table state effects visible width light attr =
    Html.div
        [ blockKeydown (UpdateTable Sub.NoOp) ]
        [ toggleBtn lang table.id "table"
        , table.body
            |> toMatrix effects visible
            |> sort state
            |> (::) (List.map (toCell effects visible) table.head)
            |> diagramTranspose attr
            |> chart lang width (table.format /= []) attr light table.class
        ]


diagramShow : Parameters -> Bool -> Bool
diagramShow attr active =
    if Param.isSet "data-show" attr then
        not active

    else
        active


diagramTranspose : Parameters -> Matrix Cell -> Matrix Cell
diagramTranspose attr matrix =
    if Param.isSet "data-transpose" attr then
        Matrix.transpose matrix

    else
        matrix


chart : Lang -> Int -> Bool -> Parameters -> Bool -> Class -> Matrix Cell -> Html Msg
chart lang width isFormated attr mode class matrix =
    let
        ( head, body ) =
            Matrix.split matrix

        labels =
            getLabels attr head
    in
    case class of
        BarChart ->
            let
                category =
                    body
                        |> List.map (List.head >> Maybe.map .string >> Maybe.withDefault "")
            in
            matrix
                |> Matrix.transpose
                |> Matrix.tail
                |> List.map
                    (\row ->
                        ( row |> List.head |> Maybe.map .string
                        , row |> List.tail |> Maybe.map (List.map .float) |> Maybe.withDefault []
                        )
                    )
                |> Chart.viewBarChart lang attr mode labels category

        PieChart ->
            if
                body
                    |> Matrix.column 0
                    |> Maybe.map (List.all isNumber)
                    |> Maybe.withDefault False
            then
                body
                    |> Matrix.map .float
                    |> List.map
                        (List.map2 (\category -> Maybe.map (Tuple.pair category.string)) head
                            >> List.filterMap identity
                        )
                    |> Chart.viewPieChart lang width attr mode labels Nothing

            else
                let
                    category =
                        head
                            |> List.tail
                            |> Maybe.withDefault []
                            |> List.map .string

                    sub =
                        body
                            |> Matrix.column 0
                            |> Maybe.map (List.map .string)

                    data =
                        body
                            |> Matrix.map .float
                            |> List.filterMap List.tail
                in
                data
                    |> List.map (List.map2 (\c -> Maybe.map (Tuple.pair c)) category >> List.filterMap identity)
                    |> Chart.viewPieChart lang width attr mode labels sub

        Funnel ->
            if
                body
                    |> Matrix.column 0
                    |> Maybe.map (List.all isNumber)
                    |> Maybe.withDefault False
            then
                body
                    |> Matrix.map .float
                    |> List.map
                        (List.map2 (\category -> Maybe.map (Tuple.pair category.string)) head
                            >> List.filterMap identity
                        )
                    |> Chart.viewFunnel lang width attr mode labels Nothing

            else
                let
                    category =
                        head
                            |> List.tail
                            |> Maybe.withDefault []
                            |> List.map .string

                    sub =
                        body
                            |> Matrix.column 0
                            |> Maybe.map (List.map .string)

                    data =
                        body
                            |> Matrix.map .float
                            |> List.filterMap List.tail
                in
                data
                    |> List.map (List.map2 (\c -> Maybe.map (Tuple.pair c)) category >> List.filterMap identity)
                    |> Chart.viewFunnel lang width attr mode labels sub

        HeatMap ->
            let
                y =
                    body
                        |> Matrix.column 0
                        |> Maybe.withDefault []
                        |> List.map .string

                x =
                    head
                        |> List.tail
                        |> Maybe.withDefault []
                        |> List.map .string
                        |> List.reverse
            in
            body
                |> Matrix.transpose
                |> Matrix.tail
                |> List.indexedMap
                    (\y_ row ->
                        row
                            |> List.indexedMap (\x_ cell -> ( x_, y_, cell.float ))
                    )
                |> Chart.viewHeatMap lang attr mode labels y x

        Radar ->
            let
                categories =
                    head
                        |> List.tail
                        |> Maybe.map (List.map .string)
                        |> Maybe.withDefault []
            in
            body
                |> List.map
                    (\row ->
                        ( row |> List.head |> Maybe.map .string |> Maybe.withDefault ""
                        , row |> List.tail |> Maybe.map (List.map .float) |> Maybe.withDefault []
                        )
                    )
                |> Chart.viewRadarChart lang attr mode labels categories

        Parallel ->
            let
                category =
                    head
                        |> List.tail
                        |> Maybe.withDefault []
                        |> List.map .string
            in
            body
                |> Matrix.transpose
                |> Matrix.tail
                |> Matrix.map .float
                |> Matrix.transpose
                |> Chart.viewParallel lang attr mode labels category

        BoxPlot ->
            body
                |> Matrix.map .float
                |> Matrix.transpose
                |> Chart.viewBoxPlot lang attr mode labels (List.map .string head)

        Graph ->
            let
                nodesA =
                    head
                        |> List.tail
                        |> Maybe.withDefault []
                        |> List.map .string

                nodesB =
                    body
                        |> Matrix.column 0
                        |> Maybe.withDefault []
                        |> List.map .string

                nodes =
                    nodesA
                        ++ nodesB
                        |> Set.fromList
                        |> Set.toList
                        |> List.filter ((/=) "")
            in
            body
                |> List.concatMap
                    (\row ->
                        case row of
                            [] ->
                                []

                            b :: values ->
                                values
                                    |> List.map2
                                        (\a v ->
                                            case v.float of
                                                Just float ->
                                                    if float == 0 then
                                                        Nothing

                                                    else
                                                        Just ( a, b.string, float )

                                                _ ->
                                                    Nothing
                                        )
                                        nodesA
                    )
                |> List.filterMap identity
                |> List.filter (\( a, b, _ ) -> a /= "" || b /= "")
                |> Chart.viewGraph lang attr mode labels nodes

        Sankey ->
            let
                nodesA =
                    head
                        |> List.tail
                        |> Maybe.withDefault []
                        |> List.map .string

                nodesB =
                    body
                        |> Matrix.column 0
                        |> Maybe.withDefault []
                        |> List.map .string

                nodes =
                    nodesA
                        ++ nodesB
                        |> Set.fromList
                        |> Set.toList
                        |> List.filter ((/=) "")
            in
            body
                |> List.concatMap
                    (\row ->
                        case row of
                            [] ->
                                []

                            b :: values ->
                                values
                                    |> List.map2
                                        (\a v ->
                                            case v.float of
                                                Just float ->
                                                    if float == 0 then
                                                        Nothing

                                                    else
                                                        Just ( a, b.string, float )

                                                _ ->
                                                    Nothing
                                        )
                                        nodesA
                    )
                |> List.filterMap identity
                |> List.filter (\( a, b, _ ) -> a /= "" || b /= "")
                |> Chart.viewSankey lang attr mode labels nodes

        Map ->
            let
                data =
                    if isFormated then
                        body

                    else
                        matrix

                categories =
                    data
                        |> Matrix.column 0
                        |> Maybe.withDefault []
                        |> List.map .string

                values =
                    data
                        |> Matrix.column 1
                        |> Maybe.withDefault []
                        |> List.map .float
                        |> List.map2 Tuple.pair categories
            in
            attr
                |> Param.get "data-src"
                |> Chart.viewMapChart lang
                    attr
                    mode
                    labels
                    values

        _ ->
            let
                xs : List (Maybe Float)
                xs =
                    body
                        |> Matrix.column 0
                        |> Maybe.withDefault []
                        |> List.map .float

                legend =
                    head
                        |> List.tail
                        |> Maybe.withDefault []
                        |> List.map .string
            in
            if
                xs
                    |> List.filterMap identity
                    |> List.length
                    |> (==) (List.length xs)
            then
                let
                    type_ name pts =
                        if class == LinePlot then
                            Lines pts (Just name)

                        else
                            Dots pts (Just name)

                    diagrams =
                        body
                            |> Matrix.transpose
                            |> Matrix.tail
                            |> Matrix.map .float
                            |> List.map
                                (List.map2 (\x y -> Maybe.map2 Point x y) xs
                                    >> List.filterMap identity
                                )
                            |> List.map2 type_ legend
                            |> List.indexedMap (\i diagram -> ( Chart.getColor i, diagram ))
                in
                { title = labels.main |> Maybe.withDefault ""
                , yLabel = labels.y |> Maybe.withDefault ""
                , xLabel = labels.x |> Maybe.withDefault ""
                , legend = legend
                , diagrams = diagrams |> Dict.fromList
                }
                    |> Chart.viewChart lang attr mode

            else
                let
                    xvalues =
                        body
                            |> Matrix.column 0
                            |> Maybe.withDefault []
                            |> List.map .string

                    xlabels =
                        head
                            |> List.tail
                            |> Maybe.withDefault []
                            |> List.map .string
                in
                body
                    |> Matrix.transpose
                    |> Matrix.tail
                    |> Matrix.map .float
                    |> List.map2 Tuple.pair xlabels
                    |> (if class == LinePlot then
                            Chart.viewLines

                        else
                            Chart.viewPoints
                       )
                        lang
                        attr
                        mode
                        labels
                        xvalues


getLabels : Parameters -> Row Cell -> Labels
getLabels attr row =
    { main =
        case Param.get "data-title" attr of
            Just title ->
                Just title

            Nothing ->
                row
                    |> List.head
                    |> Maybe.andThen (.string >> isEmpty)
    , x =
        Param.get "data-xlabel" attr
    , y =
        Param.get "data-ylabel" attr
    }


getState : Int -> Vector -> State
getState id =
    Array.get id >> Maybe.withDefault (State -1 False False)


toTable : Lang -> Int -> Parameters -> Class -> List (Html Msg) -> Html Msg
toTable lang id attr class body =
    if class == None then
        Html.table (Param.annotation "lia-table" attr) body

    else
        Html.div []
            [ toggleBtn lang id <|
                case class of
                    BarChart ->
                        "barchart"

                    PieChart ->
                        "piechart"

                    LinePlot ->
                        "lineplot"

                    HeatMap ->
                        "heatmap"

                    Radar ->
                        "radar"

                    Parallel ->
                        "parallel"

                    Graph ->
                        "graph"

                    Map ->
                        "map"

                    Sankey ->
                        "sankey"

                    ScatterPlot ->
                        "scatterplot"

                    BoxPlot ->
                        "boxplot"

                    Funnel ->
                        "funnel"

                    None ->
                        ""
            , Html.table
                (Param.annotation "lia-table" attr)
                body
            ]


toggleBtn : Lang -> Int -> String -> Html Msg
toggleBtn lang id icon =
    Html.button [ onClick <| UpdateTable <| Sub.Toggle id ]
        [ Html.img
            [ Attr.height 16
            , Attr.width 16
            , Attr.src <| "img/" ++ icon ++ ".png"
            ]
            []
        , Html.text "todo: title"
        ]


unformatted : (Inlines -> List (Html Msg)) -> Matrix Cell -> Int -> State -> List (Html Msg)
unformatted viewer rows id state =
    case sort state rows of
        head :: tail ->
            tail
                |> List.map
                    (List.map (\e -> Html.td (Attr.class "lia-table__data" :: Param.toAttribute e.attr) (viewer e.inlines))
                        >> Html.tr [ Attr.class "lia-table__row" ]
                    )
                |> (::)
                    (head
                        |> view_head1 viewer id state
                        |> Html.tr [ Attr.class "lia-table__row" ]
                    )

        [] ->
            []


formatted : (Inlines -> List (Html Msg)) -> List ( Parameters, Inlines ) -> List String -> Matrix Cell -> Int -> State -> List (Html Msg)
formatted viewer head format rows id state =
    rows
        |> sort state
        |> List.map
            (List.map2 (\f e -> Html.td (Attr.class "lia-table__data" :: Attr.class f :: Param.toAttribute e.attr) (viewer e.inlines)) format
                >> Html.tr [ Attr.class "lia-table__row" ]
            )
        |> (::)
            (head
                |> view_head2 viewer id format state
                |> Html.thead [ Attr.class "lia-table__head" ]
            )


get : Int -> List x -> Maybe x
get i =
    if i == 0 then
        List.head

    else
        List.tail >> Maybe.andThen (get (i - 1))


sort : State -> Matrix Cell -> Matrix Cell
sort state matrix =
    if state.column /= -1 then
        let
            sorted =
                if
                    matrix
                        |> Matrix.column state.column
                        |> Maybe.map (List.all isNumber)
                        |> Maybe.withDefault False
                then
                    List.sortBy
                        (get state.column
                            >> Maybe.andThen .float
                            >> Maybe.withDefault 0
                        )
                        matrix

                else
                    List.sortBy (get state.column >> Maybe.map (.string >> String.toLower) >> Maybe.withDefault "") matrix
        in
        if state.dir then
            sorted

        else
            List.reverse sorted

    else
        matrix


view_head1 : (Inlines -> List (Html Msg)) -> Int -> State -> Row Cell -> List (Html Msg)
view_head1 viewer id state =
    List.indexedMap
        (\i r ->
            header viewer id Const.align.default state i r.inlines
                |> Html.td (Attr.class Const.align.default :: Param.toAttribute r.attr)
        )


view_head2 : (Inlines -> List (Html Msg)) -> Int -> List String -> State -> List ( Parameters, Inlines ) -> List (Html Msg)
view_head2 viewer id format state =
    List.map2 Tuple.pair format
        >> List.indexedMap
            (\i ( f, ( a, r ) ) ->
                header viewer id f state i r
                    |> Html.th (Attr.class f :: Param.toAttribute a)
            )


header : (Inlines -> List (Html Msg)) -> Int -> String -> State -> Int -> Inlines -> List (Html Msg)
header viewer id format state i r =
    [ Html.span
        [ Attr.class format ]
        (viewer r)
    , Html.button
        [ Attr.class "lia-icon"
        , onClick <| UpdateTable <| Sub.Sort id i
        ]
        [ Html.i []
            [ Html.text <|
                if state.column == i && state.dir then
                    "sort up"

                else if state.column == i && not state.dir then
                    "sort down"

                else
                    "unsorted"
            ]
        ]
    ]
