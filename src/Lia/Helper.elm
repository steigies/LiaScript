module Lia.Helper exposing (..)

import Combine exposing (..)
import Combine.Char exposing (..)


type alias ID =
    Int



--newline : Parser s ()


c_frame : Parser s String
c_frame =
    string "```"


newline : Parser s Char
newline =
    --(char '\n' <|> eol) |> skip
    char '\n'


newlines : Parser s String
newlines =
    --many newline |> skip
    regex "\\n*"


newlines1 : Parser s String
newlines1 =
    --many newline |> skip
    regex "\\n+"


spaces : Parser s String
spaces =
    regex "[ \\t]*"


spaces1 : Parser s String
spaces1 =
    regex "[ \\t]+"


stringTill : Parser s p -> Parser s String
stringTill p =
    String.fromList <$> manyTill anyChar p
