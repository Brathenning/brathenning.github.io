import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import gleam/uri

import modem
import plinth/browser/window
import rsvp

import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Comment {
  Comment(
    id: Int,
    on_page: String,
    by_user: String,
    created_at: timestamp.Timestamp,
    content: option.Option(String),
    reply_to: option.Option(Int),
  )
}

pub type Msg {
  ApiReturnedComments(Result(List(Comment), rsvp.Error))
  ApiAddedComment(Result(response.Response(String), rsvp.Error))
  UserClickedAddComment
  UserEnteredName(String)
  UserEnteredComment(String)
  UserResetComment
  UserStartedReply(Int)
}

pub type Model {
  Model(
    comments: List(Comment),
    user: String,
    comment: String,
    input_disabled: Bool,
    current_page: String,
    reply_to: option.Option(Int),
  )
}

pub fn init(_args) -> #(Model, Effect(Msg)) {
  let initial_path =
    modem.initial_uri()
    |> result.map(fn(uri) { uri.path })
    |> result.unwrap("/")
  let model = Model([], "", "", False, initial_path, option.None)

  #(model, get_comment(model))
}

pub fn create_comment(model: Model) -> Result(Comment, Nil) {
  case model.user == "" {
    True -> Error(Nil)
    False ->
      Ok(Comment(
        0,
        model.current_page,
        model.user,
        timestamp.system_time(),
        {
          case model.comment {
            "" -> option.None
            content -> option.Some(content)
          }
        },
        model.reply_to,
      ))
  }
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg, model.input_disabled {
    UserClickedAddComment, False ->
      case create_comment(model) {
        Ok(comment) -> #(
          Model(..model, input_disabled: True),
          post_comment(comment),
        )
        Error(Nil) -> #(
          Model(..model, user: "must not be empty", reply_to: option.None),
          effect.none(),
        )
      }

    UserStartedReply(id), False -> {
      case id {
        0 -> #(
          Model(
            ..model,
            comment: "reload page before replying\n" <> model.comment,
          ),
          effect.none(),
        )
        _ -> #(Model(..model, reply_to: option.Some(id)), effect.none())
      }
    }

    ApiAddedComment(Ok(_)), True ->
      case create_comment(model) {
        Ok(comment) -> #(
          Model(
            ..model,
            comments: list.prepend(model.comments, comment),
            user: "",
            comment: "",
            input_disabled: False,
            reply_to: option.None,
          ),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }

    ApiAddedComment(Error(_)), True -> #(
      Model(
        ..model,
        comment: "Error posting to Api",
        input_disabled: False,
        reply_to: option.None,
      ),
      effect.none(),
    )

    ApiReturnedComments(Ok(comments)), _ -> #(
      Model(..model, comments: comments),
      effect.none(),
    )

    ApiReturnedComments(Error(_)), _ -> #(model, effect.none())

    UserEnteredComment(comment), False -> #(
      Model(..model, comment: comment),
      effect.none(),
    )
    UserEnteredName(name), False -> #(Model(..model, user: name), effect.none())
    UserResetComment, False -> #(
      Model(..model, user: "", comment: "", reply_to: option.None),
      effect.none(),
    )

    _, _ -> #(model, effect.none())
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([], {
    case model.reply_to {
      option.None -> [
        enter_comment(model),
        html.div(
          [],
          recursive_replies(
            model,
            list.group(model.comments, fn(comment) { comment.reply_to }),
            option.None,
            "",
            0,
          ),
        ),
      ]
      option.Some(_) -> [
        html.div(
          [],
          recursive_replies(
            model,
            list.group(model.comments, fn(comment) { comment.reply_to }),
            option.None,
            "",
            0,
          ),
        ),
      ]
    }
  })
}

fn enter_comment(model: Model) -> Element(Msg) {
  html.div([], [
    html.div([], [
      html.p(
        [
          attribute.styles([#("padding", "0px"), #("margin", "0px")]),
        ],
        [
          html.text("Name:"),
        ],
      ),
      html.input([
        attribute.value(model.user),
        event.on_input(UserEnteredName),
      ]),
    ]),
    html.div([], [
      html.p(
        [
          attribute.styles([#("padding", "0px"), #("margin", "0px")]),
        ],
        [
          html.text("Kommentar:"),
        ],
      ),
      html.textarea(
        [
          attribute.value(model.user),
          attribute.styles([
            #("width", "100%"),
            #("height", "50px"),
          ]),
          event.on_input(UserEnteredComment),
        ],
        model.comment,
      ),
    ]),
    html.div([], [
      html.button([event.on_click(UserClickedAddComment)], [
        html.text("Kommentieren"),
      ]),
      html.button([event.on_click(UserResetComment)], [html.text("Abbrechen")]),
    ]),
  ])
}

fn outer_div_attributes(layer: Int) -> List(attribute.Attribute(Msg)) {
  case layer {
    0 -> []
    _ -> [
      attribute.styles([
        #("padding-left", int.to_string(10) <> "px"),
        #(
          "border-left",
          "6px solid "
            <> "hsl("
            <> int.to_string({ 0 + layer * 30 })
            <> ", 100%, 82%)",
        ),
      ]),
    ]
  }
}

fn comment_div(
  comment: Comment,
  current_top: option.Option(Int),
  top_name: String,
) -> Element(Msg) {
  html.div(
    [
      attribute.class("comment"),
    ],
    [
      html.span([], [html.text(comment.by_user)]),
      html.span([], [html.text(" - ")]),
      html.span([], [
        html.text(
          timestamp.to_calendar(comment.created_at, calendar.utc_offset).0
          |> format_date,
        ),
      ]),
      html.div([], p_list(comment, current_top, top_name)),

      html.button([event.on_click(UserStartedReply(comment.id))], [
        html.text("Antworten"),
      ]),
    ],
  )
}

fn p_list(
  comment: Comment,
  current_top: option.Option(Int),
  top_name: String,
) -> List(Element(Msg)) {
  let p_comments = case
    option.unwrap(comment.content, "")
    |> string.split_once("\n")
  {
    Ok(#(first, rest)) -> #(
      first,
      rest
        |> string.split("\n")
        |> list.map(fn(content_split) {
          html.p(
            [
              attribute.styles([#("padding", "0px"), #("margin", "0px")]),
            ],
            [
              html.text(content_split),
            ],
          )
        }),
    )
    Error(_) -> #(option.unwrap(comment.content, ""), [])
  }
  case current_top {
    option.None ->
      html.p([attribute.styles([#("padding", "0px"), #("margin", "0px")])], [
        html.text(p_comments.0),
      ])
    _ ->
      html.p([attribute.styles([#("padding", "0px"), #("margin", "0px")])], [
        html.a([attribute.href("#")], [
          html.text("@" <> top_name),
        ]),
        html.text(": " <> p_comments.0),
      ])
  }
  |> list.prepend(p_comments.1, _)
}

fn recursive_replies(
  model: Model,
  comments_dict: dict.Dict(option.Option(Int), List(Comment)),
  current_top: option.Option(Int),
  top_name: String,
  layer: Int,
) -> List(Element(Msg)) {
  {
    case
      comments_dict
      |> dict.get(current_top)
    {
      Error(_) -> []
      Ok(current_comments) -> {
        [
          html.div(
            outer_div_attributes(layer),
            list.sort(current_comments, fn(com_b, com_a) {
              timestamp.compare(com_a.created_at, com_b.created_at)
            })
              |> list.map(fn(comment) {
                case
                  recursive_replies(
                    model,
                    comments_dict,
                    option.Some(comment.id),
                    comment.by_user,
                    layer + 1,
                  )
                {
                  [] ->
                    case model.reply_to {
                      option.Some(x) if x == comment.id ->
                        html.div([], [
                          comment_div(comment, current_top, top_name),
                          enter_comment(model),
                        ])
                      _ -> comment_div(comment, current_top, top_name)
                    }
                  sub_comments ->
                    html.div(
                      [],
                      [
                        case model.reply_to {
                          option.Some(x) if x == comment.id ->
                            html.div([], [
                              comment_div(comment, current_top, top_name),
                              enter_comment(model),
                            ])
                          _ -> comment_div(comment, current_top, top_name)
                        },
                      ]
                        |> list.append(sub_comments),
                    )
                }
              }),
          ),
        ]
      }
    }
  }
}

fn format_date(comment_date: calendar.Date) -> String {
  int.to_string(comment_date.day)
  <> ". "
  <> month_to_german(comment_date.month, "de")
  <> " "
  <> int.to_string(comment_date.year)
}

fn month_to_german(month: calendar.Month, lang: String) -> String {
  case month {
    calendar.January ->
      case lang {
        "at" | "AT" -> "Jänner"
        _ -> "Januar"
      }
    calendar.February ->
      case lang {
        "AT" -> "Feber"
        _ -> "Februar"
      }
    calendar.March -> "März"
    calendar.April -> "April"
    calendar.May -> "Mai"
    calendar.June -> "Juni"
    calendar.July -> "Juli"
    calendar.August -> "August"
    calendar.September -> "September"
    calendar.October -> "Oktober"
    calendar.November -> "November"
    calendar.December -> "Dezember"
  }
}

fn post_comment(new_comment: Comment) {
  let url = "https://qieprbrymjppuirdahzf.supabase.co/rest/v1/Comments"
  let assert Ok(uri) = uri.parse(url)
  let handler = rsvp.expect_ok_response(ApiAddedComment)
  let body =
    json.object([
      #("on_page", json.string(new_comment.on_page)),
      #("by_user", json.string(new_comment.by_user)),
      #(
        "created_at",
        new_comment.created_at
          |> timestamp.to_rfc3339(calendar.utc_offset)
          |> json.string(),
      ),
      #("content", json.nullable(new_comment.content, json.string)),
      #("reply_to", json.nullable(new_comment.reply_to, json.int)),
    ])

  let assert Ok(request) = request.from_uri(uri)
  request
  |> request.set_header(
    "apikey",
    "sb_publishable_X0MlBjjgRgM75O4CCKv5Rg_XLAnssQZ",
  )
  |> request.set_header(
    "Authorization",
    "Bearer sb_publishable_X0MlBjjgRgM75O4CCKv5Rg_XLAnssQZ",
  )
  |> request.set_header("content-type", "application/json")
  |> request.set_header("Prefer", "return=minimal")
  |> request.set_method(http.Post)
  |> request.set_body(json.to_string(body))
  |> echo
  |> rsvp.send(handler)
}

fn get_comment(model: Model) {
  let url =
    "https://qieprbrymjppuirdahzf.supabase.co/rest/v1/Comments?on_page=eq."
    <> model.current_page
  let assert Ok(uri) = uri.parse(url)
  let handler =
    rsvp.expect_json(decode.list(decode_comment()), ApiReturnedComments)

  let assert Ok(request) = request.from_uri(uri)
  request
  |> request.set_header(
    "apikey",
    "sb_publishable_X0MlBjjgRgM75O4CCKv5Rg_XLAnssQZ",
  )
  |> request.set_header(
    "Authorization",
    "Bearer sb_publishable_X0MlBjjgRgM75O4CCKv5Rg_XLAnssQZ",
  )
  |> request.set_method(http.Get)
  |> echo
  |> rsvp.send(handler)
}

fn decode_comment() {
  use id <- decode.field("id", decode.int)
  use on_page <- decode.field("on_page", decode.string)
  use by_user <- decode.field("by_user", decode.string)
  use created_at_str <- decode.field("created_at", decode.string)
  let created_at =
    timestamp.parse_rfc3339(created_at_str)
    |> result.unwrap(timestamp.from_calendar(
      date: calendar.Date(1970, calendar.January, 1),
      time: calendar.TimeOfDay(0, 0, 0, 0),
      offset: calendar.utc_offset,
    ))
  use content <- decode.field("content", decode.optional(decode.string))
  use reply_to <- decode.field("reply_to", decode.optional(decode.int))

  decode.success(Comment(
    id:,
    on_page:,
    by_user:,
    created_at:,
    content:,
    reply_to:,
  ))
}
