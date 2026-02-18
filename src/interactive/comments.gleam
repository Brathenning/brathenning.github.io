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
import gleam/time/calendar
import gleam/time/timestamp
import gleam/uri
import modem
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
  UserRepliedComment(Int)
}

pub type Model {
  Model(
    comments: List(Comment),
    user: String,
    comment: String,
    input_disabled: Bool,
    current_page: String,
    reply_to: Int,
  )
}

pub fn init(_args) -> #(Model, Effect(Msg)) {
  let initial_path =
    modem.initial_uri()
    |> result.map(fn(uri) { uri.path })
    |> result.unwrap("/")
  let model = Model([], "", "", False, initial_path, 0)

  #(model, get_comment(model))
}

pub fn create_comment(model: Model) -> Result(Comment, Nil) {
  case model.user == "" {
    True -> Error(Nil)
    False ->
      Ok(
        Comment(
          model.reply_to,
          model.current_page,
          model.user,
          timestamp.system_time(),
          {
            case model.comment {
              "" -> option.None
              content -> option.Some(content)
            }
          },
          {
            case model.reply_to {
              0 -> option.None
              id -> option.Some(id)
            }
          },
        ),
      )
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
          Model(..model, user: "must not be empty", reply_to: 0),
          effect.none(),
        )
      }

    UserRepliedComment(id), False ->
      case id {
        0 -> #(
          Model(
            ..model,
            comment: "reload page before replying\n" <> model.comment,
          ),
          effect.none(),
        )
        _ -> update(Model(..model, reply_to: id), UserClickedAddComment)
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
            reply_to: 0,
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
        reply_to: 0,
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
      Model(..model, user: "", comment: ""),
      effect.none(),
    )

    _, _ -> #(model, effect.none())
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.div([], [
      html.div([], [
        html.p([], [
          html.text("Name:"),
        ]),
        html.input([
          attribute.value(model.user),
          event.on_input(UserEnteredName),
        ]),
      ]),
      html.div([], [
        html.p([], [
          html.text("Kommentar:"),
        ]),
        html.textarea(
          [
            event.on_input(UserEnteredComment),
          ],
          model.comment,
        ),
      ]),
      html.div([], [
        html.button([event.on_click(UserClickedAddComment)], [
          html.text("Kommentieren"),
        ]),
        html.button([event.on_click(UserResetComment)], [html.text("Leer")]),
      ]),
    ]),
    html.div(
      [],
      recursive_replies(
        list.group(model.comments, fn(comment) { comment.reply_to }),
        option.None,
        "",
        0,
      ),
    ),
  ])
}

fn recursive_replies(
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
      Ok(current_comments) ->
        list.sort(current_comments, fn(com_a, com_b) {
          timestamp.compare(com_a.created_at, com_b.created_at)
        })
        |> list.map(fn(comment) {
          html.div(
            [
              attribute.style(
                "margin-left",
                int.to_string({ layer * 20 }) <> "px",
              ),
            ],
            list.append(
              [
                html.span([], [html.text(comment.by_user)]),
                html.span([], [html.text(" - ")]),
                html.span([], [
                  html.text(
                    timestamp.to_calendar(
                      comment.created_at,
                      calendar.utc_offset,
                    ).0
                    |> format_date,
                  ),
                ]),
                {
                  case current_top {
                    option.None ->
                      html.p([], [
                        html.text(option.unwrap(comment.content, "")),
                      ])
                    _ ->
                      html.p([], [
                        html.a([attribute.href("#")], [
                          html.text("@" <> top_name),
                        ]),
                        html.text(option.unwrap(comment.content, "")),
                      ])
                  }
                },

                html.button([event.on_click(UserRepliedComment(4))], [
                  html.text("Antworten auf " <> int.to_string(comment.id)),
                ]),
              ],
              recursive_replies(
                comments_dict,
                option.Some(comment.id),
                comment.by_user,
                layer + 1,
              ),
            ),
          )
        })
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
