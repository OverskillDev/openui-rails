# frozen_string_literal: true

require "test_helper"

class LexerTest < Minitest::Test
  L = OpenUI::Lang::Lexer

  def types(src)
    L.tokenize(src).map(&:type)
  end

  def test_identifiers_split_by_case
    toks = L.tokenize('root = Card("x", child, $state, @Count)')
    assert_equal %i[ident equals type lparen str comma ident comma state_var comma builtin_call rparen eof], toks.map(&:type)
    assert_equal "Card", toks[2].value
    assert_equal "$state", toks[8].value
    assert_equal "Count", toks[10].value
  end

  def test_double_quoted_strings_use_json_escapes
    tok = L.tokenize('"q\"d\\\\b\ttA"').first
    assert_equal "q\"d\\b\ttA", tok.value
  end

  def test_single_quoted_strings_support_four_escapes
    assert_equal "it's\n\\x", L.tokenize("'it\\'s\\n\\\\\\x'").first.value
  end

  def test_unterminated_string_is_closed_implicitly
    tok = L.tokenize('"abc').first
    assert_equal :str, tok.type
    assert_equal "abc", tok.value
  end

  def test_numbers_integer_and_float
    toks = L.tokenize("42, -3, 1.5, 1e3, 2.")
    nums = toks.select { |t| t.type == :num }
    assert_equal [42, -3, 1.5, 1000.0, 2], nums.map(&:value)
    assert_kind_of Integer, nums[0].value
    assert_equal %i[num dot eof], toks.last(3).map(&:type)
  end

  def test_minus_after_value_is_subtraction
    assert_equal %i[num minus num eof], types("1 -2")
    assert_equal %i[num comma num eof], types("1, -2")
  end

  def test_operators_and_single_ampersand
    assert_equal %i[ident and ident or ident eqeq num noteq num gte lte not question colon eof], types("a & b || c == 1 != 2 >= <= ! ? :")
  end

  def test_unknown_characters_are_skipped
    assert_equal %i[ident ident eof], types("a;b")
  end

  def test_string_length_cap
    tok = L.tokenize("\"#{"x" * 50}\"", max_string_length: 10).first
    assert_equal 10, tok.value.length
  end
end
