import interactive/cats
import interactive/comments
import lustre

pub fn main() {
  let app = lustre.application(cats.init, cats.update, cats.view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  let app = lustre.application(comments.init, comments.update, comments.view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}
