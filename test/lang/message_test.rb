# frozen_string_literal: true

require "test_helper"

class MessageTest < Minitest::Test
  M = OpenUI::Lang::Message

  def test_round_trip
    stored = M.build(content: "root = Card([t])\nt = Text(\"x\")", context: {"formState" => {"note" => "rush"}},
      attributes: {"library" => "support@1.2.0"}, end: true)
    assert_equal "]]>openui:content?library=support%401.2.0\nroot = Card([t])\nt = Text(\"x\")\n]]>openui:context\n{\"formState\":{\"note\":\"rush\"}}\n]]>openui:end", stored
    parsed = M.parse(stored)
    assert_equal "root = Card([t])\nt = Text(\"x\")", parsed.content
    assert_equal({"formState" => {"note" => "rush"}}, parsed.context)
    assert_equal({"library" => "support@1.2.0"}, parsed.attributes)
    assert parsed.end?
  end

  def test_plain_text_is_content
    parsed = M.parse("root = Card([])")
    assert_equal "root = Card([])", parsed.content
    assert_nil parsed.context
    refute parsed.end?
  end

  def test_last_content_wins
    raw = "]]>openui:content\nold\n]]>openui:end\n]]>openui:content\nnew"
    assert_equal "new", M.parse(raw).content
    refute M.parse(raw).end?
  end

  def test_streaming_holds_back_partial_marker
    assert_equal "root = Card([])", M.parse("root = Card([])\n]]>open", streaming: true).content
  end

  def test_strip_for_model
    assert_equal "a = 1", M.strip("]]>openui:content\na = 1\n]]>openui:context\n{}\n]]>openui:end")
  end
end
