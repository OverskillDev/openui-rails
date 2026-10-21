# frozen_string_literal: true

require "test_helper"
require "openui"
require "webmock/minitest"
require "ruby_llm"
require "openui/ruby_llm"

# Drives a real RubyLLM::Chat against a stubbed OpenAI Chat Completions SSE
# response whose events split statements mid-line, so the parser's chunk
# handling is exercised through chat.ask itself.
class RubyLLMIntegrationTest < Minitest::Test
  include OpenUI::TestSupport

  PROGRAM_CHUNKS = [
    "root = Stack([title, tab",
    "le])\ntitle = Text(\"Pl",
    "ans\", \"heading\")\ntable = Table([plan, price])\n",
    "plan = Col(\"Plan\", [\"Starter\", \"Team\"])\nprice = Col(\"USD\", [19, 49], \"right\")\n"
  ].freeze

  def setup
    RubyLLM.configure { |c| c.openai_api_key = "test-key" }
    @library = OpenUI::Library.from_spec(fixture_spec)
    @library = starter_library
  end

  def starter_library
    OpenUI::Library.define(id: "t", root: "Stack") do
      component("Stack", description: "Layout") do
        arg :children, list(component)
        arg :direction, enum("column", "row"), optional: true
      end
      component("Text", description: "Text") do
        arg :text, string
        arg :variant, enum("body", "heading"), optional: true
      end
      component("Table", description: "Table") { arg :columns, list(component("Col")) }
      component("Col", description: "Column") do
        arg :label, string
        arg :data, list(any)
        arg :align, enum("left", "right"), optional: true
      end
    end
  end

  def sse_body(chunks)
    events = chunks.each_with_index.map do |text, i|
      finish = (i == chunks.length - 1) ? "stop" : nil
      JSON.generate({"id" => "chatcmpl-1", "object" => "chat.completion.chunk", "model" => "gpt-test",
                     "choices" => [{"index" => 0, "delta" => {"role" => "assistant", "content" => text}, "finish_reason" => finish}]})
    end
    events.map { |e| "data: #{e}\n\n" }.join + "data: [DONE]\n\n"
  end

  def stub_completion(chunks = PROGRAM_CHUNKS)
    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .to_return(status: 200, headers: {"Content-Type" => "text/event-stream"}, body: sse_body(chunks))
  end

  def chat
    RubyLLM.chat(model: "gpt-test", provider: :openai, assume_model_exists: true, protocol: :chat_completions)
  end

  def test_with_openui_injects_the_library_prompt_as_a_system_message
    c = chat.with_instructions("Be brief.").with_openui(@library)
    system = c.messages.select { |m| m.role == :system }.map(&:content)
    assert_equal ["Be brief.", @library.prompt], system
    assert_same @library, c.openui_library
  end

  def test_with_openui_can_replace_and_take_prompt_options
    c = chat.with_instructions("Old.").with_openui(@library, append: false, preamble: "Custom preamble.")
    system = c.messages.select { |m| m.role == :system }.map(&:content)
    assert_equal 1, system.length
    assert system.first.start_with?("Custom preamble.\n")
  end

  def test_ask_openui_streams_events_and_returns_a_parsed_response
    stub_completion
    events = []
    response = chat.with_openui(@library).ask_openui("Compare the plans") { |e| events << e }
    assert_equal PROGRAM_CHUNKS.join, response.program
    assert_equal "Stack", response.result.root.type
    assert_equal %w[Text Table], response.result.root.props["children"].map(&:type)
    assert_empty response.result.errors
    assert response.result.complete
    types = events.map(&:type)
    assert_equal 4, types.count(:chunk)
    assert_includes types, :statement
    assert_equal :end, types.last
    intermediate = events.select { |e| e.type == :result && !e.complete }
    assert_equal "Stack", intermediate.first.result.root.type, "the shell renders after the first chunk"
    assert_equal [], intermediate.first.result.root.props["children"]
    assert_equal PROGRAM_CHUNKS.join, response.message.content
  end

  def test_on_openui_event_handlers_fire
    stub_completion
    seen = []
    c = chat.with_openui(@library).on_openui_event { |e| seen << e.type }
    c.ask_openui("go")
    assert_includes seen, :result
    assert_equal :end, seen.last
  end

  def test_ask_openui_without_library_raises
    assert_raises(ArgumentError) { chat.ask_openui("x") }
  end

  def test_stream_can_be_driven_by_any_chunk_source
    stream = OpenUI::RubyLLM::Stream.new(@library)
    results = []
    stream.on_event { |e| results << e.result if e.type == :result }
    PROGRAM_CHUNKS.each { |c| stream.push(c) }
    final = stream.finish
    assert_equal 2, final.root.props["children"].length
    assert results.length >= PROGRAM_CHUNKS.length
  end
end
