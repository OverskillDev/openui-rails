# frozen_string_literal: true

require "test_helper"

class StatementsTest < Minitest::Test
  S = OpenUI::Lang::Statements

  def test_fences_are_joined_and_prose_ignored
    text = "Here:\n```openui\nroot = Stack([a])\n```\nmore prose\n```\na = Text(\"x\")\n"
    assert_equal "root = Stack([a])\n\na = Text(\"x\")\n", S.strip_fences(text)
  end

  def test_backticks_inside_double_quoted_strings_do_not_close_a_fence
    text = "```\nroot = Stack([Text(\"use ``` here\")])\n```"
    assert_equal "root = Stack([Text(\"use ``` here\")])\n", S.strip_fences(text)
  end

  def test_comments_stripped_outside_strings
    assert_equal "a = Text(\"x // y\")\nb = 1", S.strip_comments("a = Text(\"x // y\") // note\n# whole line\nb = 1".sub("# whole line\n", "")).gsub(/\n\n/, "\n")
    assert_equal "", S.strip_comments("# only a comment")
  end

  def test_auto_close_strings_and_brackets
    assert_equal ["Card([Text(\"a\")])", true], S.auto_close("Card([Text(\"a")
    assert_equal ["x = \"a\\\\\"", true], S.auto_close("x = \"a\\")
    assert_equal ["done", false], S.auto_close("done")
  end

  def test_split_skips_lines_without_statement_shape
    toks = OpenUI::Lang::Lexer.tokenize("just prose here\nroot = Stack([])\n= bad\nx\n")
    stmts = S.split(toks)
    assert_equal ["root"], stmts.map(&:id)
  end

  def test_split_keeps_multiline_ternary_together
    toks = OpenUI::Lang::Lexer.tokenize("s = $n > 0\n  ? \"some\"\n  : \"none\"\nt = 1")
    stmts = S.split(toks)
    assert_equal %w[s t], stmts.map(&:id)
  end
end
