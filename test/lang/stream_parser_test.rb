# frozen_string_literal: true

require "test_helper"

class StreamParserTest < Minitest::Test
  include OpenUI::TestSupport

  def test_split_mid_token_renders_a_valid_tree_after_every_chunk
    sp = fixture_stream_parser
    r1 = sp.push("root = Stack([header, kpis])\nheader = Te")
    assert_equal "Stack", r1.root.type
    assert_equal [], r1.root.props["children"]
    r2 = sp.push("xt(\"Tickets\", \"heading\")\nkpis = Stack([open")
    assert_equal %w[Text Stack], r2.root.props["children"].map(&:type)
    assert r2.incomplete
    r3 = sp.push(", closed])\nopen = Metric(\"Open\", 1)\nclosed = Metric(\"Closed\", 8)\n")
    assert_equal 2, r3.root.props["children"][1].props["children"].length
    refute r3.incomplete
    final = sp.finish
    assert final.complete
    assert_empty final.errors
  end

  def test_pending_never_overwrites_completed
    sp = fixture_stream_parser
    sp.push("root = Stack([t])\nt = Text(\"done\")\n")
    r = sp.push("t = Text(\"part")
    assert_equal "done", r.root.props["children"].first.props["text"]
    final = sp.finish
    assert_equal "part", final.root.props["children"].first.props["text"]
  end

  def test_statement_callbacks_fire_once_per_completed_statement
    seen = []
    sp = fixture_stream_parser.on_statement { |id, kind| seen << [id, kind] }
    sp.push("root = Stack([t])\nt = Te")
    assert_equal [["root", :value]], seen
    sp.push("xt(\"x\")\n")
    # A trailing newline leaves the last statement provisional (4 rule 1).
    assert_equal [["root", :value]], seen
    sp.push("u = 1")
    assert_equal [["root", :value], ["t", :value]], seen
    sp.finish
    assert_equal [["root", :value], ["t", :value], ["u", :value]], seen
  end

  def test_set_replaces_when_text_is_not_an_extension
    sp = fixture_stream_parser
    sp.set("root = Stack([Text(\"a\")])")
    r = sp.set("root = Stack([Text(\"b\")])", complete: true)
    assert_equal "b", r.root.props["children"].first.props["text"]
  end

  def test_input_cap_stops_accepting_and_reports
    sp = OpenUI::Lang::StreamParser.new(fixture_schema, root: "Stack", limits: OpenUI::Lang::Limits.default.merge(max_input_bytes: 40))
    sp.push("root = Stack([Text(\"a\")])\n")
    r = sp.push("t = Text(\"#{"x" * 100}\")\n", complete: true)
    assert sp.truncated?
    assert_includes r.errors.map(&:code), "limit-exceeded"
    assert_equal "Stack", r.root.type
  end

  def test_pending_tail_cap
    sp = OpenUI::Lang::StreamParser.new(fixture_schema, root: "Stack", limits: OpenUI::Lang::Limits.default.merge(max_pending_bytes: 30))
    r = sp.push("root = Stack([Text(\"#{"y" * 200}")
    assert r.truncated
  end
end
