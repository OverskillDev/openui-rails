# frozen_string_literal: true

require_relative "rails_test_helper"

class CatalogComponentsTest < ActiveSupport::TestCase
  include OpenUI::RailsTestSupport

  def library
    @library ||= OpenUI::Rails::CatalogLibrary.build
  end

  def render(program, mount_id: "c")
    result = library.parse(program)
    renderer = OpenUI::Rails::Renderer.new(library, view_context: view_context, mount_id: mount_id)
    html = renderer.render(result)
    assert_empty result.errors.map(&:to_h)
    assert_empty renderer.errors.map(&:to_h)
    doc(html)
  end

  test "Section, Divider and Badge" do
    d = render('root = Section("Usage", [Divider("Today"), Divider(), Badge("Healthy", "success"), Badge("Draft")], "Last 7 days")')
    assert_equal "Usage", d.at_css(".openui-section h2").text
    assert_equal "Last 7 days", d.at_css(".openui-section header p").text
    assert_equal "Today", d.at_css(".openui-divider[role=separator]").text.strip
    assert d.at_css("hr.openui-divider")
    assert_includes d.css(".openui-badge")[0]["class"], "bg-green-50"
    assert_includes d.css(".openui-badge")[1]["class"], "bg-gray-100", "neutral by default"
  end

  test "Markdown formats a safe subset and escapes everything else" do
    d = render(<<~'OUI')
      root = Markdown("# Title\nSome **bold** and *it* and `a**b`.\n\n- one\n- two <b>\n\n1. first\n\n<script>alert(1)</script> [x](javascript:alert(1))")
    OUI
    md = d.at_css(".openui-markdown")
    assert_equal "Title", md.at_css("h3").text
    assert_equal "bold", md.at_css("strong").text
    assert_equal "it", md.at_css("em").text
    assert_equal "a**b", md.at_css("code").text
    assert_equal ["one", "two <b>"], md.css("ul li").map(&:text)
    assert_equal ["first"], md.css("ol li").map(&:text)
    assert_nil md.at_css("script")
    assert_nil md.at_css("a")
    assert_includes md.text, "<script>alert(1)</script>"
  end

  test "Metric formats the value, the unit and the delta" do
    d = render('root = Stack([Metric("Revenue", 48200, "$", 12.5, "vs last month"), Metric("Churn", 2.1, "%", -0.4), Metric("Seats", 40, "seats", 0)])')
    metrics = d.css(".openui-metric")
    assert_equal "$48,200", metrics[0].css("p")[1].text
    assert_includes metrics[0].text, "+12.5%"
    assert metrics[0].at_css(".text-green-600 svg")
    assert_equal "2.1%", metrics[1].css("p")[1].text
    assert metrics[1].at_css(".text-red-600")
    assert_equal "40 seats", metrics[2].css("p")[1].text
  end

  test "List, Checklist and Timeline" do
    d = render(<<~OUI)
      root = Stack([List(["a", "b"]), List(["x"], "ordered"), Checklist([{label: "Done", done: true}, {label: "Todo"}], "Launch"), Timeline([{title: "Signed", time: "Mon", text: "Contract"}, {title: "Kickoff"}])])
    OUI
    assert_equal %w[a b], d.css("ul.openui-list li").map(&:text)
    assert d.at_css("ol.openui-list.list-decimal")
    items = d.css(".openui-checklist li")
    assert_includes items[0].text, "(done)"
    assert items[0].at_css(".line-through")
    assert_nil items[1].at_css(".line-through")
    assert_equal ["Signed", "Kickoff"], d.css(".openui-timeline li p.font-semibold").map(&:text)
  end

  test "Form controls render inert with labels" do
    d = render(<<~OUI)
      root = Form("signup", [email, plan, terms, notes, send], "Start a trial")
      email = Input("email", "Work email", "you@company.com", "email")
      plan = Select("plan", ["Starter", "Team"], "Plan", "Team")
      terms = Checkbox("terms", "I agree", true)
      notes = Input("notes", "Notes", null, "textarea")
      send = Button("Start trial", @ToAssistant("Start my trial", {plan: "Team"}))
    OUI
    form = d.at_css("div.openui-form[role=form][data-openui-form=signup]")
    assert form
    assert_nil d.at_css("form")
    input = form.at_css("input[type=email][name=email]")
    assert_equal "you@company.com", input["placeholder"]
    assert_equal input["id"], form.at_css("label[for='#{input["id"]}']")["for"]
    assert_equal "Team", form.at_css("select option[selected]").text
    assert form.at_css("input[type=checkbox][checked]")
    assert form.at_css("textarea[name=notes]")
    button = form.at_css("button.openui-button[type=button]")
    assert_equal [{"type" => "continue_conversation", "message" => "Start my trial", "context" => {"plan" => "Team"}}], JSON.parse(button["data-openui-action"])
  end

  test "Button with OpenUrl shows the url and an external-link icon" do
    d = render('root = Button("Docs", @OpenUrl("https://example.com/docs"), "secondary")')
    button = d.at_css("button")
    assert_equal "https://example.com/docs", button["title"]
    assert_equal [{"type" => "open_url", "url" => "https://example.com/docs"}], JSON.parse(button["data-openui-action"])
    assert_includes button["class"], "ring-gray-300"
  end

  test "Image and Avatar load https sources only" do
    d = render(<<~OUI)
      root = Stack([Image("Chart", "https://example.com/a.png", "Q3"), Image("Slot", "javascript:alert(1)"), Image("Proto", "//evil.example/x.png"), Avatar("Ada Lovelace", "CTO"), Avatar("Grace", null, "http://example.com/g.png")])
    OUI
    imgs = d.css(".openui-image")
    assert_equal "https://example.com/a.png", imgs[0].at_css("img")["src"]
    assert_equal "Q3", imgs[0].at_css("figcaption").text
    assert_nil imgs[1].at_css("img")
    assert_equal "Slot", imgs[1].at_css("[role=img]")["aria-label"]
    assert_nil imgs[2].at_css("img")
    avatars = d.css(".openui-avatar")
    assert_equal "AL", avatars[0].at_css("span").text
    assert_equal "GR", avatars[1].at_css("span").text
    assert_nil avatars[1].at_css("img")
  end
end
