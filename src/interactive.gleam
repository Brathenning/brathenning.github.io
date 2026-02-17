import gleam/int
import lustre
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

type Model =
  Int

type Msg {
  UserClickedIncrement
  UserClickedDecrement
}

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

fn init(_args) -> Model {
  0
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    UserClickedIncrement -> model + 1
    UserClickedDecrement -> model - 1
  }
}

fn view(model: Model) -> Element(Msg) {
  let count = int.to_string(model)

  html.div([], [
    html.button([event.on_click(UserClickedIncrement)], [html.text("+")]),
    html.p([], [html.text(count)]),
    html.button([event.on_click(UserClickedDecrement)], [html.text("-")]),
  ])
}
