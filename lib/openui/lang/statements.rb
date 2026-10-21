# frozen_string_literal: true

module OpenUI
  module Lang
    # Source preparation (language.md 1.2), implicit closing of a streaming
    # tail (section 4 rule 2) and the statement splitter (section 1.4).
    # Ported from the reference parser (packages/lang-core/src/parser/
    # parser.ts and statements.ts, MIT).
    module Statements
      RawStatement = Struct.new(:id, :id_type, :tokens)

      module_function

      # Fence extraction, comment stripping, trimming, in that order.
      def preprocess(text)
        strip_comments(strip_fences(text.strip)).strip
      end

      # Skip over a double-quoted string starting at +start+; returns the index
      # after its closing quote (or the text length when unclosed).
      def skip_string(input, start)
        return start unless input[start] == '"'
        i = start + 1
        while i < input.length
          c = input[i]
          if c == "\\"
            i += 2
          elsif c == '"'
            return i + 1
          else
            i += 1
          end
        end
        i
      end

      def fence_at?(input, i)
        input[i] == "`" && input[i + 1] == "`" && input[i + 2] == "`"
      end

      # Join the contents of every ``` fence; without fences return the text.
      # Backtick runs inside double-quoted strings do not open or close a fence.
      def strip_fences(input)
        blocks = []
        i = 0
        while i < input.length
          fence_start = -1
          while i < input.length
            next_i = skip_string(input, i)
            if next_i > i
              i = next_i
              next
            end
            if fence_at?(input, i)
              fence_start = i
              break
            end
            i += 1
          end
          break if fence_start == -1

          j = fence_start + 3
          j += 1 while j < input.length && input[j] != "\n"
          if j >= input.length
            blocks << input[(fence_start + 3)..].sub(/\A[^\n]*\n?/, "")
            i = input.length
            break
          end
          j += 1

          close_pos = -1
          k = j
          while k < input.length
            next_k = skip_string(input, k)
            if next_k > k
              k = next_k
              next
            end
            if fence_at?(input, k)
              close_pos = k
              break
            end
            k += 1
          end

          if close_pos != -1
            blocks << input[j...close_pos]
            i = close_pos + 3
          else
            blocks << input[j..]
            i = input.length
          end
        end

        return blocks.join("\n") unless blocks.empty?

        if input.start_with?("```")
          j = 3
          j += 1 while j < input.length && input[j] != "\n"
          start = j < input.length ? j + 1 : 3
          body = input[start..] || ""
          trailing = body.rindex("```")
          return trailing ? body[0...trailing] : body
        end

        input
      end

      # Remove // and # comments outside strings. String state carries across
      # lines so a multi-line string keeps its comment markers.
      def strip_comments(input)
        in_str = nil
        input.split("\n", -1).map do |line|
          out = line
          i = 0
          while i < line.length
            c = line[i]
            if in_str
              if c == "\\" && i + 1 < line.length
                i += 2
                next
              end
              in_str = nil if c == in_str
              i += 1
              next
            end
            if c == '"' || c == "'"
              in_str = c
              i += 1
              next
            end
            if c == "/" && line[i + 1] == "/"
              out = line[0...i].rstrip
              break
            end
            if c == "#"
              out = line[0...i].rstrip
              break
            end
            i += 1
          end
          out
        end.join("\n")
      end

      # Close an unterminated string (adding a backslash first when the text
      # ends mid-escape) and unclosed brackets in reverse order.
      # @return [Array(String, Boolean)] the closed text and whether it was incomplete
      def auto_close(input, max_depth: nil)
        stack = []
        in_str = nil
        esc = false
        input.each_char do |c|
          if esc
            esc = false
            next
          end
          if c == "\\" && in_str
            esc = true
            next
          end
          if in_str
            in_str = nil if c == in_str
            next
          end
          if c == '"' || c == "'"
            in_str = c
            next
          end
          case c
          when "(", "[", "{"
            stack << c
          when ")" then stack.pop if stack.last == "("
          when "]" then stack.pop if stack.last == "["
          when "}" then stack.pop if stack.last == "{"
          end
          return [input, true] if max_depth && stack.length > max_depth
        end

        incomplete = !in_str.nil? || !stack.empty?
        return [input, false] unless incomplete

        out = input.dup
        if in_str
          out << "\\" if esc
          out << in_str
        end
        stack.reverse_each do |open|
          out << {"(" => ")", "[" => "]", "{" => "}"}[open]
        end
        [out, true]
      end

      OPENERS = [T::LPAREN, T::LBRACK, T::LBRACE].freeze
      CLOSERS = [T::RPAREN, T::RBRACK, T::RBRACE].freeze

      # Split a token stream into `name = expression` statements. Lines without
      # that shape are skipped silently. Newlines inside brackets or an open
      # ternary do not end a statement.
      def split(tokens)
        stmts = []
        pos = 0
        len = tokens.length
        while pos < len
          pos += 1 while pos < len && tokens[pos].type == T::NEWLINE
          break if pos >= len || tokens[pos].type == T::EOF

          tok = tokens[pos]
          unless [T::IDENT, T::TYPE, T::STATE_VAR].include?(tok.type)
            pos += 1 while pos < len && tokens[pos].type != T::NEWLINE && tokens[pos].type != T::EOF
            next
          end
          id = tok.value
          id_type = tok.type
          pos += 1

          if pos >= len || tokens[pos].type != T::EQUALS
            pos += 1 while pos < len && tokens[pos].type != T::NEWLINE && tokens[pos].type != T::EOF
            next
          end
          pos += 1

          expr = []
          depth = 0
          ternary_depth = 0
          while pos < len && tokens[pos].type != T::EOF
            tt = tokens[pos].type
            if tt == T::NEWLINE && depth <= 0 && ternary_depth <= 0
              peek = pos + 1
              peek += 1 while peek < len && tokens[peek].type == T::NEWLINE
              next_t = peek < len ? tokens[peek].type : T::EOF
              if next_t == T::QUESTION || (next_t == T::COLON && ternary_depth > 0)
                pos += 1
                next
              end
              break
            end
            if tt == T::NEWLINE
              pos += 1
              next
            end
            if OPENERS.include?(tt)
              depth += 1
            elsif CLOSERS.include?(tt) && depth > 0
              depth -= 1
            elsif tt == T::QUESTION && depth == 0
              ternary_depth += 1
            elsif tt == T::COLON && depth == 0 && ternary_depth > 0
              ternary_depth -= 1
            end
            expr << tokens[pos]
            pos += 1
          end

          stmts << RawStatement.new(id, id_type, expr) unless expr.empty?
        end
        stmts
      end
    end
  end
end
