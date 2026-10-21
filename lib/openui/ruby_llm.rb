# frozen_string_literal: true

require_relative "../openui"

module OpenUI
  # RubyLLM integration (rubyllm.com). Works with RubyLLM 1.16 and 2.x: both
  # have with_instructions(text, append: true) and yield Chunk#content to the
  # ask/complete block. No callback API is relied on.
  #
  #   chat = RubyLLM.chat.with_openui(library)
  #   response = chat.ask_openui("Compare these 3 plans") do |event|
  #     broadcast(progressive.update(event.result)) if event.type == :result
  #   end
  #   response.result.root   # OpenUI::Lang::Element
  #   response.program       # the OpenUI Lang text the model wrote
  module RubyLLM
    Event = Struct.new(:type, :chunk, :result, :complete, :statement_id, keyword_init: true)
    Response = Struct.new(:message, :result, :program, :library, keyword_init: true)

    # Feed any chunk source into a streaming parse and get events out.
    class Stream
      attr_reader :library, :parser

      def initialize(library, limits: Lang::Limits.default, placeholders: false)
        @library = library
        @parser = library.stream_parser(limits: limits, placeholders: placeholders)
        @handlers = []
        @last = nil
        @parser.on_statement { |id, _kind| emit(Event.new(type: :statement, statement_id: id)) }
      end

      def on_event(&block)
        @handlers << block
        self
      end

      def push(text, chunk: nil)
        return @last if text.nil? || text.empty?
        emit(Event.new(type: :chunk, chunk: chunk)) if chunk
        @last = parser.push(text)
        emit(Event.new(type: :result, result: @last, complete: false))
        @last
      end

      def finish
        @last = parser.finish
        emit(Event.new(type: :result, result: @last, complete: true))
        emit(Event.new(type: :end, result: @last, complete: true))
        @last
      end

      def result
        @last || parser.result
      end

      def text
        parser.text
      end

      private

      def emit(event)
        @handlers.each { |h| h.call(event) }
      end
    end

    # Mixed into RubyLLM::Chat (and acts_as_chat records).
    module ChatExtension
      # Inject the library's system prompt (prompt.md section 4). Appends to
      # existing instructions by default; pass append: false to replace them.
      # Extra keyword options go to Library#prompt (preamble:, examples:,
      # additional_rules:, ...). On an acts_as_chat record the system message
      # is persisted like any with_instructions call.
      def with_openui(library, append: true, instructions_options: {}, **prompt_options)
        @openui_library = library
        with_instructions(library.prompt(**prompt_options), append: append, **instructions_options)
        self
      end

      def openui_library
        @openui_library
      end

      # Register a handler for OpenUI events during ask_openui.
      def on_openui_event(&block)
        (@openui_handlers ||= []) << block
        self
      end

      # ask, with the streamed content parsed as OpenUI Lang. Yields Event
      # objects (type :chunk, :statement, :result, :end). Returns a Response.
      def ask_openui(message = nil, library: nil, with: nil, limits: Lang::Limits.default, placeholders: false, &block)
        library ||= openui_library or raise ArgumentError, "call with_openui(library) first or pass library:"
        stream = Stream.new(library, limits: limits, placeholders: placeholders)
        Array(@openui_handlers).each { |h| stream.on_event(&h) }
        stream.on_event(&block) if block
        reply = ask(message, with: with) do |chunk|
          content = chunk.respond_to?(:content) ? chunk.content : chunk.to_s
          stream.push(content, chunk: chunk) if content.is_a?(String) && !content.empty?
        end
        # A provider that did not stream still returns the full message.
        stream.push(reply.content) if stream.text.empty? && reply.respond_to?(:content) && reply.content.is_a?(String)
        result = stream.finish
        Response.new(message: reply, result: result, program: stream.text, library: library)
      end
    end

    class << self
      # Add with_openui / ask_openui to RubyLLM::Chat and to acts_as_chat records.
      def install!
        return false unless defined?(::RubyLLM::Chat)
        ::RubyLLM::Chat.include(ChatExtension) unless ::RubyLLM::Chat.include?(ChatExtension)
        if defined?(::RubyLLM::ActiveRecord::ChatMethods) && !::RubyLLM::ActiveRecord::ChatMethods.include?(ChatExtension)
          ::RubyLLM::ActiveRecord::ChatMethods.include(ChatExtension)
        end
        true
      end

      # The instruction text with_openui injects, for hosts that assemble
      # prompts themselves (for example in an append region rather than the
      # system prompt).
      def instructions_for(library, **prompt_options)
        library.prompt(**prompt_options)
      end
    end
  end
end

OpenUI::RubyLLM.install! if defined?(::RubyLLM::Chat)
