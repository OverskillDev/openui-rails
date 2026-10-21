# frozen_string_literal: true

require "test_helper"

class ParserTest < Minitest::Test
  include OpenUI::TestSupport

  def parse(text, **limits)
    fixture_parser(limits: OpenUI::Lang::Limits.default.merge(limits)).parse(text)
  end

  def test_forward_references_resolve
    r = parse("root = Stack([a])\na = Text(\"later\")")
    assert_equal "Text", r.root.props["children"].first.type
    assert_equal "a", r.root.props["children"].first.statement_id
    assert_empty r.errors
  end

  def test_unknown_component_dropped_rest_renders
    r = parse("root = Stack([Text(\"a\"), Bogus(1)])")
    assert_equal 1, r.root.props["children"].length
    assert_equal ["unknown-component"], r.errors.map(&:code)
    assert_includes r.errors.first.hint, "Available components"
  end

  def test_lines_without_statement_shape_are_dropped_silently
    r = parse("Sure, here you go:\nroot = Stack([Text(\"a\")])\nHope that helps!")
    assert_equal "Stack", r.root.type
    assert_empty r.errors
  end

  def test_statement_cap
    program = (["root = Stack([t0])"] + (0..50).map { |i| "t#{i} = Text(\"#{i}\")" }).join("\n")
    r = parse(program, max_statements: 10)
    assert r.truncated
    assert_includes r.errors.map(&:code), "limit-exceeded"
    assert_equal "Stack", r.root.type
  end

  def test_input_byte_cap
    r = parse("root = Stack([Text(\"#{"x" * 1000}\")])", max_input_bytes: 100)
    assert r.truncated
  end

  def test_depth_cap_marks_incomplete
    r = parse("root = Stack([#{"[" * 100}1#{"]" * 100}])", max_depth: 8)
    assert r.incomplete
  end

  def test_element_cap
    program = "root = Stack([#{Array.new(30) { "Text(\"x\")" }.join(", ")}])"
    r = parse(program, max_elements: 5)
    assert_equal 4, r.root.props["children"].length
    assert_includes r.errors.map(&:code), "limit-exceeded"
  end

  def test_each_cap
    r = parse("root = Stack(@Each([1,2,3,4,5], \"n\", Text(\"\" + n)))", max_each_items: 2)
    assert_equal 2, r.root.props["children"].length
  end

  def test_non_utf8_input_is_scrubbed
    text = "root = Stack([Text(\"caf\xE9\")])".dup.force_encoding("ASCII-8BIT")
    r = parse(text)
    assert_equal "Stack", r.root.type
  end

  def test_reportable_errors_hide_stream_only_conditions
    r = fixture_parser.parse("page = Stack([Metric(\"x\")])", complete: false)
    assert_includes r.errors.map(&:code), "no-root"
    refute_includes r.reportable_errors.map(&:code), "no-root"
  end
end

class ParserPlaceholderTest < Minitest::Test
  include OpenUI::TestSupport

  def parser
    OpenUI::Lang::Parser.new(fixture_schema, root: "Stack", placeholders: true)
  end

  def test_unresolved_component_refs_become_placeholders_only_in_slots
    r = parser.parse("root = Stack([a, Card(\"T\", [body]), Col(\"n\", [missingNumber])])", complete: false)
    children = r.root.props["children"]
    assert_equal OpenUI::Lang::Placeholder.new("a"), children[0]
    assert_equal [OpenUI::Lang::Placeholder.new("body")], children[1].props["children"]
    # Col.data is an untyped list here ({"type": "array"}), which may hold components, so the placeholder stays.
    assert_equal [OpenUI::Lang::Placeholder.new("missingNumber")], children[2].props["data"]
    assert_equal %w[a body missingNumber], r.unresolved
  end

  def test_unresolved_required_scalar_keeps_a_skeleton_while_streaming_then_drops
    r = parser.parse("root = Stack([c])\nc = Card(title, [])", complete: false)
    assert_equal [OpenUI::Lang::Placeholder.new("c")], r.root.props["children"]
    r = parser.parse("root = Stack([c])\nc = Card(title, [])", complete: true)
    assert_equal [], r.root.props["children"]
    assert_equal ["null-required"], r.errors.map(&:code)
  end

  def test_half_written_reference_keeps_the_statement_skeleton
    r = parser.parse("root = Stack([chart])\nchart = Ch", complete: false)
    assert_equal [OpenUI::Lang::Placeholder.new("chart")], r.root.props["children"]
  end

  def test_no_placeholders_once_the_stream_is_complete
    r = parser.parse("root = Stack([a])", complete: true)
    assert_equal [], r.root.props["children"]
  end

  def test_default_parser_drops_unresolved_refs
    r = fixture_parser.parse("root = Stack([a])")
    assert_equal [], r.root.props["children"]
  end
end
