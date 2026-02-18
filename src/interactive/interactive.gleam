import interactive/cats
import interactive/comments
import lustre

pub fn main() {
  let cats = lustre.application(cats.init, cats.update, cats.view)
  let assert Ok(_) = lustre.start(cats, "#cat", Nil)

  let comment =
    lustre.application(comments.init, comments.update, comments.view)
  let assert Ok(_) = lustre.start(comment, "#comment", Nil)

  Nil
}
