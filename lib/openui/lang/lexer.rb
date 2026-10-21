# frozen_string_literal: true

require "json"

module OpenUI
  module Lang
    # Tokenizer for OpenUI Lang source text. A port of the reference lexer
    # (thesysdev/openui, packages/lang-core/src/parser/lexer.ts, MIT) following
    # language.md section 1.3. Lexing never fails: a character that matches no
    # rule is skipped.
    module Lexer
      module_function

      ALPHA = /[A-Za-z_]/
      ALNUM = /[A-Za-z0-9_]/
      DIGIT = /[0-9]/

      SINGLE_CHAR = {
        "(" => T::LPAREN, ")" => T::RPAREN, "[" => T::LBRACK, "]" => T::RBRACK,
        "{" => T::LBRACE, "}" => T::RBRACE, "," => T::COMMA, ":" => T::COLON,
        "." => T::DOT, "?" => T::QUESTION, "+" => T::PLUS, "*" => T::STAR,
        "/" => T::SLASH, "%" => T::PERCENT
      }.freeze

      KEYWORDS = {"true" => T::TRUE, "false" => T::FALSE, "null" => T::NULL}.freeze

      # @param src [String]
      # @param max_string_length [Integer, nil] cap on one string literal (host safety limit)
      # @return [Array<Token>]
      def tokenize(src, max_string_length: nil)
        tokens = []
        i = 0
        n = src.length

        while i < n
          c = src[i]

          if c == " " || c == "\t" || c == "\r"
            i += 1
            next
          end

          if c == "\n"
            tokens << Token.new(T::NEWLINE)
            i += 1
            next
          end

          if (type = SINGLE_CHAR[c])
            tokens << Token.new(type)
            i += 1
            next
          end

          case c
          when "="
            if src[i + 1] == "="
              tokens << Token.new(T::EQEQ)
              i += 2
            else
              tokens << Token.new(T::EQUALS)
              i += 1
            end
            next
          when "!"
            if src[i + 1] == "="
              tokens << Token.new(T::NOTEQ)
              i += 2
            else
              tokens << Token.new(T::NOT)
              i += 1
            end
            next
          when ">"
            if src[i + 1] == "="
              tokens << Token.new(T::GTE)
              i += 2
            else
              tokens << Token.new(T::GT)
              i += 1
            end
            next
          when "<"
            if src[i + 1] == "="
              tokens << Token.new(T::LTE)
              i += 2
            else
              tokens << Token.new(T::LT)
              i += 1
            end
            next
          when "&"
            tokens << Token.new(T::AND)
            i += (src[i + 1] == "&") ? 2 : 1
            next
          when "|"
            tokens << Token.new(T::OR)
            i += (src[i + 1] == "|") ? 2 : 1
            next
          when '"'
            value, i = lex_double_quoted(src, i, max_string_length)
            tokens << Token.new(T::STR, value)
            next
          when "'"
            value, i = lex_single_quoted(src, i, max_string_length)
            tokens << Token.new(T::STR, value)
            next
          when "-"
            prev = tokens.last
            after_value = prev && T::VALUE_TOKENS.include?(prev.type)
            unless !after_value && DIGIT.match?(src[i + 1].to_s)
              tokens << Token.new(T::MINUS)
              i += 1
              next
            end
            # else: negative number literal, handled below
          end

          if DIGIT.match?(c) || (c == "-" && DIGIT.match?(src[i + 1].to_s))
            value, i = lex_number(src, i)
            tokens << Token.new(T::NUM, value)
            next
          end

          if c == "$" && ALPHA.match?(src[i + 1].to_s)
            start = i
            i += 1
            i += 1 while i < n && ALNUM.match?(src[i])
            tokens << Token.new(T::STATE_VAR, src[start...i])
            next
          end

          if ALPHA.match?(c)
            start = i
            i += 1 while i < n && ALNUM.match?(src[i])
            word = src[start...i]
            if (kw = KEYWORDS[word])
              tokens << Token.new(kw)
            else
              kind = ("A".."Z").cover?(c) ? T::TYPE : T::IDENT
              tokens << Token.new(kind, word)
            end
            next
          end

          if c == "@" && ALPHA.match?(src[i + 1].to_s)
            i += 1
            start = i
            i += 1 while i < n && ALNUM.match?(src[i])
            tokens << Token.new(T::BUILTIN_CALL, src[start...i])
            next
          end

          i += 1 # any other character is skipped (spec 1.3)
        end

        tokens << Token.new(T::EOF)
        tokens
      end

      # Double-quoted strings use JSON escapes. Like the reference lexer, the raw
      # literal is handed to the JSON parser; an unterminated literal (streaming)
      # is closed first. When JSON rejects it (raw newline, broken escape) the
      # quotes are stripped and the raw text is kept.
      def lex_double_quoted(src, i, max_len)
        n = src.length
        start = i
        i += 1
        closed = false
        while i < n
          if src[i] == "\\"
            i += 2
          elsif src[i] == '"'
            i += 1
            closed = true
            break
          else
            i += 1
          end
        end
        i = n if i > n
        raw = src[start...i]
        json_text = closed ? raw : raw + '"'
        value = begin
          parsed = JSON.parse(json_text)
          parsed.is_a?(String) ? parsed : raw.sub(/\A"/, "").sub(/"\z/, "")
        rescue JSON::ParserError
          raw.sub(/\A"/, "").sub(/"\z/, "")
        end
        value = value[0, max_len] if max_len && value.length > max_len
        [value, i]
      end

      # Single-quoted strings support only \' \\ \n \t; other escapes keep the character.
      def lex_single_quoted(src, i, max_len)
        n = src.length
        i += 1
        out = +""
        while i < n
          ch = src[i]
          if ch == "\\"
            i += 1
            if i < n
              esc = src[i]
              out << case esc
                     when "'" then "'"
                     when "\\" then "\\"
                     when "n" then "\n"
                     when "t" then "\t"
                     else esc
                     end
              i += 1
            end
          elsif ch == "'"
            i += 1
            break
          else
            out << ch
            i += 1
          end
        end
        out = out[0, max_len] if max_len && out.length > max_len
        [out, i]
      end

      # Numbers: -?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?  (spec 1.3). Integers stay
      # Integer, anything with a fraction or exponent becomes Float, so a table
      # cell shows 3 rather than 3.0.
      def lex_number(src, i)
        n = src.length
        start = i
        i += 1 if src[i] == "-"
        i += 1 while i < n && DIGIT.match?(src[i])
        is_float = false
        if src[i] == "." && DIGIT.match?(src[i + 1].to_s)
          is_float = true
          i += 1
          i += 1 while i < n && DIGIT.match?(src[i])
        end
        if src[i] == "e" || src[i] == "E"
          exp_start = i
          i += 1
          i += 1 if src[i] == "+" || src[i] == "-"
          digits_start = i
          i += 1 while i < n && DIGIT.match?(src[i])
          if i == digits_start
            # Dangling exponent: implementation-defined (spec 1.6). Keep the mantissa.
            text = src[start...exp_start]
            return [is_float ? Float(text) : Integer(text, 10), i]
          end
          is_float = true
        end
        text = src[start...i]
        value = is_float ? Float(text) : Integer(text, 10)
        [value, i]
      end
    end
  end
end
