# frozen_string_literal: true

require_relative "rails_test_helper"

class RendererTest < ActiveSupport::TestCase
  include OpenUI::RailsTestSupport

  test "renders every starter component from the canned program" do
    html, renderer, result = render_program(CANNED, mount_id: "m")
    assert_empty result.errors.reject(&:warning?)
    assert_empty renderer.errors
    d = doc(html)
    assert d.at_css("div#m-root.openui-node .openui-stack--column"), "Stack with a stable id"
    assert_equal "Three plans for a six-person team", d.at_css("#m-title h2.openui-text--heading").text
    table = d.at_css("#m-table table.openui-table")
    assert_equal %w[Plan Price\ per\ month\ (USD) Seats Cost\ per\ seat\ for\ 6\ people], table.css("th").map(&:text)
    assert_equal 3, table.css("tbody tr").length
    assert_equal "19", table.css("tbody tr")[0].css("td")[1].text
    assert table.css("th")[1]["class"].include?("openui-table__cell--right")
    kv = d.at_css("#m-kv .openui-kv")
    assert_equal "At a glance", kv.at_css(".openui-kv__title").text
    assert_equal ["Cheapest that fits 6", "Needs 2 plans", "SSO"], kv.css("dt").map(&:text)
    chart = d.at_css("#m-chart figure.openui-chart")
    assert_equal 3, chart.css("rect.openui-chart__bar").length
    assert_equal ["Starter x6", "Team x2", "Business"], chart.css("text.openui-chart__label").map(&:text)
    note = d.at_css("#m-note aside.openui-callout--tip")
    assert_equal "Recommendation", note.at_css(".openui-callout__title").text
  end

  test "renders Card with children and a line Chart" do
    html, = render_program(<<~OUI)
      root = Stack([Card("Trend", [c], "last 4 weeks")])
      c = Chart(["w1", "w2", "w3", "w4"], [{name: "Visits", data: [10, 14, 9, 20]}, {name: "Signups", data: [1, 2, 1, 3]}], "line")
    OUI
    d = doc(html)
    assert_equal "Trend", d.at_css(".openui-card__title").text
    assert_equal "last 4 weeks", d.at_css(".openui-card__subtitle").text
    assert_equal 2, d.css("polyline.openui-chart__line").length
    assert_equal %w[Visits Signups], d.css(".openui-chart__legend-item").map { |li| li.text.strip }
  end

  test "escapes model text everywhere" do
    payload = "<script>alert(1)</script> & <b>bold</b>"
    html, = render_program(<<~OUI)
      root = Stack([Text(#{payload.inspect}, "heading"), Callout(#{payload.inspect}, "danger", #{payload.inspect}), kv, t])
      kv = KeyValue([{label: #{payload.inspect}, value: #{payload.inspect}}], #{payload.inspect})
      t = Table([Col(#{payload.inspect}, [#{payload.inspect}])], #{payload.inspect})
    OUI
    refute_includes html, "<script>"
    refute_includes html, "<b>bold</b>"
    assert_equal 9, html.scan("&lt;script&gt;alert(1)&lt;/script&gt; &amp; &lt;b&gt;bold&lt;/b&gt;").length
  end

  test "unknown components never reach the renderer and the rest renders" do
    html, _, result = render_program('root = Stack([Text("ok"), Bogus("x"), Image("https://x/y.png")])')
    assert_equal %w[unknown-component unknown-component], result.errors.map(&:code)
    assert_includes html, "ok"
    refute_includes html, "Bogus"
    refute_includes html, "x/y.png"
  end

  test "optional defaults from the library are applied when rendering" do
    html, = render_program('root = Stack([Text("plain"), Callout("note")])')
    d = doc(html)
    assert d.at_css("p.openui-text--body")
    assert d.at_css("aside.openui-callout--info")
    assert d.at_css(".openui-stack--column")
  end

  test "a partial that raises is contained and recorded" do
    lib = OpenUI::Library.define(root: "Stack") do
      component("Stack", description: "s", renders: ->(_locals) { raise "boom" }) { arg :children, list(component) }
      component("Text", description: "t", renders: "openui/components/text") { arg :text, string }
    end
    renderer = OpenUI::Rails::Renderer.new(lib, view_context: view_context)
    html = renderer.render(lib.parse('root = Stack([Text("x")])'))
    assert_includes html, 'class="openui-render-error"'
    assert_equal ["render-error"], renderer.errors.map(&:code)
    assert_equal "Stack", renderer.errors.first.component
  end

  test "placeholders render skeleton nodes with the final dom id" do
    html, = render_program("root = Stack([later, Text(\"now\")])", placeholders: true, mount_id: "p")
    d = doc(html)
    skeleton = d.at_css("#p-later")
    assert skeleton
    assert_includes skeleton["class"], "openui-pending"
    assert_equal "true", skeleton["aria-busy"]
    html_off, = render_program("root = Stack([later, Text(\"now\")])", placeholders: false, mount_id: "p")
    assert_nil doc(html_off).at_css("#p-later")
  end

  test "text formats numbers like JavaScript and data as JSON" do
    renderer = OpenUI::Rails::Renderer.new(starter, view_context: view_context)
    assert_equal "3", renderer.text(3.0)
    assert_equal "2.5", renderer.text(2.5)
    assert_equal "true", renderer.text(true)
    assert_equal '{"a":[1,2]}', renderer.text({"a" => [1, 2]})
    assert_equal "", renderer.text(nil)
  end

  test "openui_render helper wraps the tree in a mount" do
    html = view_context.openui_render('root = Stack([Text("hi")])', library: starter, mount_id: "answer-1")
    d = doc(html)
    assert d.at_css("div#answer-1.openui-root")
    assert_equal "hi", d.at_css("#answer-1-root p").text
  end

  test "pie Chart draws one slice per positive value with a label legend" do
    html, renderer, result = render_program(<<~OUI)
      root = Chart(["Direct", "Search", "Referral", "None"], [{name: "Visits", data: [50, 30, 20, 0]}], "pie")
    OUI
    assert_empty result.errors
    assert_empty renderer.errors
    d = doc(html)
    assert d.at_css("figure.openui-chart--pie svg.openui-chart__svg--pie")
    assert_equal 3, d.css("path.openui-chart__slice").length
    assert_equal "Direct: 50", d.at_css("path.openui-chart__slice title").text
    assert_equal %w[Direct Search Referral None], d.css(".openui-chart__legend-item").map { |li| li.text.strip }
  end

  test "pie Chart with one positive value is a full circle" do
    html, = render_program('root = Chart(["All"], [{name: "n", data: [7]}], "pie")')
    assert doc(html).at_css("circle.openui-chart__slice")
  end

  test "Col sort marks the header with aria-sort and an arrow" do
    html, renderer, result = render_program(<<~OUI)
      root = Table([name, mrr])
      name = Col("Account", ["Acme", "Globex"])
      mrr = Col("MRR", [900, 400], "right", "desc")
    OUI
    assert_empty result.errors
    assert_empty renderer.errors
    th = doc(html).css("th")
    assert_nil th[0]["aria-sort"]
    assert_equal "descending", th[1]["aria-sort"]
    assert th[1].at_css("svg.openui-table__sort")
  end

  test "trace records html and direct children per statement" do
    _, renderer, = render_program("root = Stack([a, b])\na = Card(\"A\", [c])\nb = Text(\"B\")\nc = Text(\"C\")", mount_id: "t")
    assert_equal %w[a b], renderer.trace["root"].children
    assert_equal %w[c], renderer.trace["a"].children
    assert_includes renderer.trace["a"].html, renderer.trace["c"].html
  end
end
