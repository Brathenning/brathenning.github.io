import filepath
import frontmatter
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/time/calendar
import gleam/time/timestamp
import lustre/attribute
import lustre/element
import lustre/element/html
import mork
import simplifile
import tom
import webls/rss

// Where to output the built website. This can be anywhere you like.
const out_directory = "./priv"

// Directory containing our static assets
const static_directory = "./static"

const blog_directory = "./blog"

type BlogPost {
  BlogPost(
    /// The part of the URL to identify this blog post. The URL will look
    /// something like https://blog.me/<slug>.html
    slug: String,
    /// The contents of the blog post as HTML
    contents: String,
    title: String,
    description: String,
    date: calendar.Date,
  )
}

pub fn main() -> Nil {
  let blog_posts = collect_blog_posts()
  let index_page = page(element.to_string(index(blog_posts)))

  // Delete old output directory to ensure no files are left over
  let _ = simplifile.delete(out_directory)
  // Copy all our static assets to the output directory
  let assert Ok(Nil) =
    simplifile.copy_directory(static_directory, out_directory)
  // Write the index page to our file system.
  let assert Ok(Nil) =
    simplifile.write(filepath.join(out_directory, "index.html"), index_page)

  list.each(blog_posts, fn(post) {
    let path = filepath.join(out_directory, post.slug <> ".html")

    let assert Ok(Nil) = simplifile.write(path, page(post.contents))
  })

  let feed = build_feed(blog_posts)
  let assert Ok(Nil) = simplifile.write("feed.xml", rss.to_string([feed]))

  io.println("Build succeeded!")
}

fn build_feed(blog_posts: List(BlogPost)) -> rss.RssChannel {
  let items =
    list.map(blog_posts, fn(post) {
      let url = "https://brathenning.github.io/" <> post.slug <> ".html"

      rss.item(post.title, post.description)
      |> rss.with_item_link(url)
      |> rss.with_item_pub_date(timestamp.from_calendar(
        post.date,
        // If you want to add more precise timings to publishing dates you can,
        // but I since our `date` field only contains the day, we just assume
        // midnight.
        calendar.TimeOfDay(0, 0, 0, 0),
        calendar.utc_offset,
      ))
    })

  rss.channel(
    "Mein Blog",
    "Mal schauen, was so drin sein wird",
    "https://blog.me",
  )
  |> rss.with_channel_items(items)
}

fn page(contents: String) -> String {
  "<!doctype html><html>
<head><link rel=\"stylesheet\" href=\"/style.css\" /></head>
<body>" <> contents <> "</body>
</html>"
}

// View for our home page.
fn index(posts: List(BlogPost)) -> element.Element(_) {
  html.main([], [
    html.h1([], [html.text("Hennis glühender Blog!")]),
    ..list.map(posts, post)
  ])
}

fn post(post: BlogPost) -> element.Element(_) {
  let url = "/" <> post.slug <> ".html"
  let date =
    int.to_string(post.date.day)
    <> " "
    <> month_to_german(post.date.month, "de")
    <> ", "
    <> int.to_string(post.date.year)

  html.div([], [
    html.h2([], [html.a([attribute.href(url)], [html.text(post.title)])]),
    html.span([], [html.text(date)]),
    html.span([], [html.text(" - ")]),
    html.span([], [html.text(post.description)]),
  ])
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

fn collect_blog_posts() -> List(BlogPost) {
  let assert Ok(posts) = simplifile.get_files(blog_directory)

  list.map(posts, fn(post) {
    let slug = post |> filepath.base_name |> filepath.strip_extension

    let assert Ok(contents) = simplifile.read(post)

    let assert frontmatter.Extracted(
      frontmatter: option.Some(frontmatter),
      content:,
    ) = frontmatter.extract(contents)
    let html_content = content |> mork.parse |> mork.to_html

    let assert Ok(metadata) = tom.parse(frontmatter)
    let assert Ok(title) = tom.get_string(metadata, ["title"])
    let assert Ok(description) = tom.get_string(metadata, ["description"])
    let assert Ok(date) = tom.get_date(metadata, ["date"])

    BlogPost(slug:, contents: html_content, title:, description:, date:)
  })
  |> list.sort(fn(a, b) { calendar.naive_date_compare(b.date, a.date) })
}
