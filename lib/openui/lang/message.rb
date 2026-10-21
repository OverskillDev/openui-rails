# frozen_string_literal: true

require "uri"

module OpenUI
  module Lang
    # The message protocol of prompt.md section 7: a stored response wrapped in
    # `]]>openui:content`, `]]>openui:context` and `]]>openui:end` marker lines.
    # The model never sees these lines. Ported from message.ts (MIT).
    module Message
      PREFIX = "]]>openui:"
      MARKER = /\A\]\]>openui:([a-z]+)(?:\?(.*))?\z/
      RETRY = /([^\n])(?=\]\]>openui:content(?:\?|\r?\n|\z))/
      RETRY_CUT = /[^\n](\]\]>[a-z:]*)\z/

      Parsed = Struct.new(:content, :context, :attributes, :end, keyword_init: true) do
        def end?
          self.end
        end
      end

      module_function

      def encode(s)
        URI.encode_www_form_component(s.to_s).gsub("%7E", "~").tr("*", "*")
      end

      def decode(s)
        URI.decode_www_form_component(s.to_s)
      rescue ArgumentError
        s.to_s
      end

      def read_attributes(query)
        out = {}
        query.to_s.split("&").each do |pair|
          next if pair.empty?
          eq = pair.index("=")
          key = decode(eq ? pair[0...eq] : pair)
          next if key.empty?
          out[key] = eq ? decode(pair[(eq + 1)..]) : ""
        end
        out
      end

      # Split a stored message into content, context, attributes and end flag.
      # Pass streaming: true while the text is still arriving to hold back a
      # last line that may become a marker.
      def parse(raw, streaming: false)
        text = raw.to_s.gsub(RETRY, "\\1\n")
        if streaming && (cut = RETRY_CUT.match(text)) && "#{PREFIX}content".start_with?(cut[1])
          text = text[0..cut.begin(1) - 1]
        end
        lines = text.split("\n", -1)
        last = lines.last
        held = streaming && last != "" && (last.start_with?(PREFIX) || PREFIX.start_with?(last))
        lines.pop if held

        sections = [{kind: nil, attributes: {}, lines: []}]
        close = lambda do
          body = sections.last[:lines]
          body[-1] = body[-1].sub(/\r\z/, "") unless body.empty?
        end
        end_at = -1
        lines.each_with_index do |line, i|
          m = MARKER.match(line.sub(/\r\z/, ""))
          unless m
            sections.last[:lines] << line
            next
          end
          close.call
          if m[1] == "end"
            end_at = sections.length - 1
            break if i == lines.length - 2 && lines[i + 1] == ""
            next
          end
          sections << {kind: m[1], attributes: read_attributes(m[2]), lines: []}
        end
        close.call if held

        kinds = sections.map { |s| s[:kind] }
        win = [0, kinds.rindex("content") || -1].max
        ctx_i = kinds.rindex("context")
        context = (ctx_i && ctx_i > win) ? sections[ctx_i][:lines].join("\n") : nil
        if context.is_a?(String)
          begin
            context = JSON.parse(context)
          rescue JSON::ParserError
            # not JSON (yet): keep the raw text
          end
        end
        winner = sections[win]
        Parsed.new(content: winner[:lines].join("\n"), context: context, attributes: winner[:attributes], end: end_at >= win)
      end

      # Write a stored message with its marker lines.
      def build(content:, context: nil, attributes: nil, end: false)
        query = (attributes || {}).map { |k, v| "#{encode(k)}=#{encode(v)}" }.join("&")
        out = +"#{PREFIX}content#{query.empty? ? "" : "?#{query}"}\n#{content}"
        unless context.nil?
          out << "\n#{PREFIX}context\n#{context.is_a?(String) ? context : JSON.generate(context)}"
        end
        binding.local_variable_get(:end) ? "#{out}\n#{PREFIX}end" : out
      end

      # Text the model may see: the content of a stored message with no marker lines.
      def strip(raw)
        parse(raw).content
      end
    end
  end
end
