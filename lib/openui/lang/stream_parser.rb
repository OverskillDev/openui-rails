# frozen_string_literal: true

require "set"

module OpenUI
  module Lang
    # Streaming parser (language.md section 4): accepts text a chunk at a time
    # and produces a valid ParseResult after every chunk. Completed statements
    # are parsed once; the pending tail is parsed on every chunk after implicit
    # closing. Ported from createStreamParser in the reference parser (MIT).
    class StreamParser
      attr_reader :parser, :text

      def initialize(schema, root: nil, functions: {}, limits: Limits.default, placeholders: false)
        @parser = Parser.new(schema, root: root, functions: functions, limits: limits, placeholders: placeholders)
        @limits = limits
        @on_statement = []
        @on_result = []
        reset
      end

      # Called with (id, kind) each time a statement completes.
      def on_statement(&block)
        @on_statement << block
        self
      end

      # Called with (result, complete) after every push and at finish.
      def on_result(&block)
        @on_result << block
        self
      end

      # Feed the next chunk. Pass complete: true with the last chunk, or call #finish.
      def push(chunk, complete: false)
        append(chunk.to_s)
        emit(current_result(complete), complete)
      end

      # Set the full text so far; diffs against the buffer and resets if replaced.
      def set(full_text, complete: false)
        full_text = full_text.to_s
        reset if full_text.length < @buf.length || !full_text.start_with?(@buf)
        delta = full_text[@buf.length..] || ""
        append(delta) unless delta.empty?
        emit(current_result(complete), complete)
      end

      # The host ends the stream (4 rule 7): the pending tail is finalized.
      def finish
        emit(current_result(true), true)
      end

      def result(complete: false)
        current_result(complete)
      end

      def truncated?
        @truncated
      end

      def reset
        @buf = +""
        @cleaned = +""
        @completed_end = 0
        @completed = {} # id => classified statement
        @completed_count = 0
        @truncated = false
        @text = @buf
      end

      private

      def emit(result, complete)
        @on_result.each { |cb| cb.call(result, complete) }
        result
      end

      def append(chunk)
        chunk = Parser.utf8(chunk)
        return if @truncated || chunk.empty?
        if @limits && @buf.bytesize + chunk.bytesize > @limits.max_input_bytes
          room = @limits.max_input_bytes - @buf.bytesize
          chunk = room.positive? ? chunk.byteslice(0, room).scrub("") : ""
          @truncated = true
        end
        @buf << chunk
      end

      def add_statement(text)
        t = text.strip
        return if t.empty?
        Statements.split(Lexer.tokenize(t, max_string_length: @limits&.max_string_length)).each do |raw|
          stmt = @parser.classify(raw)
          @completed[raw.id] = stmt
          @completed_count += 1
          @on_statement.each { |cb| cb.call(raw.id, stmt[:kind]) }
        end
      end

      # Recompute the prepared text; if the completed prefix changed (a fence
      # opener arrived), discard the cache and scan again from the start (4 rule 4).
      def refresh_cleaned
        nxt = Statements.preprocess(@buf)
        unless nxt.start_with?(@cleaned[0, @completed_end])
          @completed_end = 0
          @completed.clear
          @completed_count = 0
        end
        @cleaned = nxt
      end

      # Advance over newly completed statements; returns where the pending tail starts.
      def scan_new_completed
        depth = 0
        ternary = 0
        in_str = nil
        esc = false
        stmt_start = @completed_end
        i = @completed_end
        len = @cleaned.length
        while i < len
          c = @cleaned[i]
          if esc
            esc = false
            i += 1
            next
          end
          if c == "\\" && in_str
            esc = true
            i += 1
            next
          end
          if in_str
            in_str = nil if c == in_str
            i += 1
            next
          end
          if c == '"' || c == "'"
            in_str = c
            i += 1
            next
          end
          case c
          when "(", "[", "{" then depth += 1
          when ")", "]", "}" then depth = [0, depth - 1].max
          when "?" then ternary += 1 if depth.zero?
          when ":" then ternary -= 1 if depth.zero? && ternary.positive?
          when "\n"
            if depth <= 0 && ternary <= 0
              peek = i + 1
              peek += 1 while peek < len && [" ", "\t", "\r", "\n"].include?(@cleaned[peek])
              if peek < len && (@cleaned[peek] == "?" || (@cleaned[peek] == ":" && ternary.positive?))
                i += 1
                next
              end
              t = @cleaned[stmt_start...i].strip
              add_statement(t) unless t.empty?
              stmt_start = i + 1
              @completed_end = i + 1
            end
          end
          i += 1
        end
        stmt_start
      end

      def current_result(complete)
        refresh_cleaned
        pending_start = scan_new_completed
        pending_text = @cleaned[pending_start..].to_s.strip
        if @limits && pending_text.bytesize > @limits.max_pending_bytes
          pending_text = pending_text.byteslice(0, @limits.max_pending_bytes).scrub("")
          @truncated = true
        end

        if pending_text.empty?
          return finalize(ParseResult.empty(incomplete: false, complete: complete)) if @completed_count.zero?
          return finalize(@parser.build(@completed.dup, incomplete: false, count: @completed_count, complete: complete))
        end

        closed, incomplete = Statements.auto_close(pending_text, max_depth: @limits&.max_depth)

        # The host ended the stream (4 rule 7): implicit closing applies and the
        # pending statements become completed, a redefinition included (2.4).
        if complete
          @completed_end = @cleaned.length
          add_statement(closed)
          return finalize(ParseResult.empty(incomplete: incomplete, complete: true)) if @completed_count.zero?
          return finalize(@parser.build(@completed.dup, incomplete: incomplete, count: @completed_count, complete: true))
        end

        raws = Statements.split(Lexer.tokenize(closed, max_string_length: @limits&.max_string_length))
        if raws.empty?
          return finalize(ParseResult.empty(incomplete: incomplete, complete: complete)) if @completed_count.zero?
          return finalize(@parser.build(@completed.dup, incomplete: incomplete, count: @completed_count, complete: complete))
        end

        # New ids render progressively; a completed id is replaced only when
        # the pending expression needed no implicit closing (4 rule 3).
        all = @completed.dup
        pending_ids = Set.new
        raws.each do |raw|
          next if @completed.key?(raw.id) && incomplete
          all[raw.id] = @parser.classify(raw)
          pending_ids << raw.id
        end

        # A `$name` ending the raw text may still be growing (`$d` of `$dishes`).
        tail = complete ? nil : @buf[/\$\w+\z/]
        pending = nil
        if tail && pending_text.end_with?(tail) && !pending_text[0...-tail.length].match?(/#{Regexp.escape(tail)}(?!\w)/)
          pending = {name: tail, ids: pending_ids}
        end

        finalize(@parser.build(all, incomplete: incomplete, count: @completed_count + raws.length,
          complete: complete, pending: pending))
      end

      def finalize(result)
        if @truncated
          result.truncated = true
          unless result.errors.any? { |e| e.code == "limit-exceeded" }
            result.errors << Error.new(source: "host", code: "limit-exceeded",
              message: "Response exceeded a host limit; parsing stopped", hint: "Shorten the program")
          end
        end
        result
      end
    end
  end
end
