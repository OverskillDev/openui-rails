# frozen_string_literal: true

require_relative "rails_test_helper"

class ProgressiveTest < ActiveSupport::TestCase
  include OpenUI::RailsTestSupport

  def stream_tags(chunks, placeholders: true)
    progressive = OpenUI::Rails::Progressive.new(starter, mount_id: "ans", view_context: view_context, placeholders: placeholders)
    parser = starter.stream_parser(placeholders: placeholders)
    batches = []
    chunks.each { |c| batches << progressive.update(parser.push(c)) }
    batches << progressive.finish(parser.finish)
    batches
  end

  def tags_of(batch)
    batch.map { |t| t.match(/action="(\w+)" target="([^"]+)"/).captures }
  end

  test "first render fills the mount, later statements replace only their own node" do
    batches = stream_tags([
      "root = Stack([title, note])\n",
      "title = Text(\"Hello\", \"heading\")\n",
      "note = Callout(\"Careful\", \"warning\")\n"
    ])
    assert_equal [["update", "ans"]], tags_of(batches[0])
    assert_equal [["replace", "ans-title"]], tags_of(batches[1]), "the title arrives: only its skeleton is replaced"
    assert_equal [["replace", "ans-note"]], tags_of(batches[2])
    assert_equal [], batches[3], "finish with nothing new sends nothing"
    assert_includes batches[1].first, 'id="ans-title"'
    assert_includes batches[1].first, "Hello"
  end

  test "without placeholders a new child replaces the nearest statement node" do
    batches = stream_tags(["root = Stack([title])\n", "title = Text(\"Hello\")\n"], placeholders: false)
    assert_equal [["update", "ans"]], tags_of(batches[0])
    assert_equal [["replace", "ans-root"]], tags_of(batches[1])
  end

  test "a chunk that changes nothing visible emits nothing" do
    batches = stream_tags(["root = Stack([t])\nt = Text(\"a\")\n", "// a comment line\n"])
    assert_equal [], batches[1]
  end

  test "a redefined statement replaces its node, not the root" do
    batches = stream_tags(["root = Stack([t, u])\nt = Text(\"a\")\nu = Text(\"b\")\n", "t = Text(\"a2\")\n"])
    assert_equal [["replace", "ans-t"]], tags_of(batches[1])
  end

  test "nested change replaces the deepest changed node" do
    batches = stream_tags([
      "root = Stack([card])\ncard = Card(\"C\", [inner])\n",
      "inner = Text(\"deep\")\n"
    ])
    assert_equal [["replace", "ans-inner"]], tags_of(batches[1])
  end

  test "losing the root empties the mount" do
    progressive = OpenUI::Rails::Progressive.new(starter, mount_id: "ans", view_context: view_context)
    first = progressive.update(starter.parse("root = Stack([Text(\"x\")])"))
    assert_equal [["update", "ans"]], tags_of(first)
    gone = progressive.update(starter.parse("nothing = 1"))
    assert_equal [["update", "ans"]], tags_of(gone)
    assert_includes gone.first, "<template></template>"
  end

  test "sse formats multi-line turbo streams as data lines" do
    out = OpenUI::Rails::SSE.event(["<turbo-stream action=\"update\" target=\"a\"><template>\n<p>x</p>\n</template></turbo-stream>"])
    assert_equal "data: <turbo-stream action=\"update\" target=\"a\"><template>\ndata: <p>x</p>\ndata: </template></turbo-stream>\n\n", out
    assert_equal "", OpenUI::Rails::SSE.event([])
    assert_equal ": keepalive\n\n", OpenUI::Rails::SSE.comment
  end
end

class ProgressivePlaceholderStabilityTest < ActiveSupport::TestCase
  include OpenUI::RailsTestSupport

  test "a partially streamed statement keeps its skeleton until it validates" do
    progressive = OpenUI::Rails::Progressive.new(starter, mount_id: "ans", view_context: view_context, placeholders: true)
    parser = starter.stream_parser(placeholders: true)
    progressive.update(parser.push("root = Stack([title, chart])\ntitle = Text(\"T\")\n"))
    # The required series argument has not arrived: the Chart does not validate yet.
    mid = progressive.update(parser.push("chart = Chart([\"a\", \"b\""))
    assert_equal [], mid, "the chart skeleton stays while the statement is incomplete"
    done = progressive.update(parser.push("], [{name: \"s\", data: [1, 2]}])\n"))
    assert_equal [["replace", "ans-chart"]], done.map { |t| t.match(/action="(\w+)" target="([^"]+)"/).captures }
  end
end
