# frozen_string_literal: true

# Streams one answer as Turbo Stream SSE events. With OPENAI_API_KEY or
# OPENROUTER_API_KEY set it asks a real model through RubyLLM; otherwise it
# replays a canned program in chunks so the demo works offline.
class DemoStreamer
  CANNED = <<~OUI
    root = Stack([title, table, kv, chart, note])
    title = Text("Three plans for a six-person team", "heading")
    table = Table([plan, price, seats, perSeat])
    plan = Col("Plan", ["Starter", "Team", "Business"])
    price = Col("Price per month (USD)", [19, 49, 99], "right")
    seats = Col("Seats", [1, 5, 25], "right")
    perSeat = Col("Cost per seat for 6 people", [114, 98, 99], "right")
    kv = KeyValue([{label: "Cheapest that fits 6", value: "Business"}, {label: "Needs 2 plans", value: "Team (5 seats)"}, {label: "SSO", value: "Business only"}], "At a glance")
    chart = Chart(["Starter x6", "Team x2", "Business"], [{name: "Monthly cost", data: [114, 98, 99]}], "bar", "Monthly cost for 6 people")
    note = Callout("Team is $1 cheaper per month but needs two subscriptions and has no SSO. Business is the simpler choice.", "tip", "Recommendation")
  OUI

  attr_reader :run, :library

  def initialize(run, library: OpenUI::Rails.library)
    @run = run
    @library = library
  end

  def live?
    ENV["OPENAI_API_KEY"].present? || ENV["OPENROUTER_API_KEY"].present?
  end

  # Yields SSE strings.
  def each_event
    progressive = OpenUI::Rails::Progressive.new(library, mount_id: run.mount_id, placeholders: true)
    stream = OpenUI::RubyLLM::Stream.new(library, placeholders: true)
    stream.on_event do |event|
      next unless event.type == :result
      tags = progressive.update(event.result, complete: event.complete)
      yield OpenUI::Rails::SSE.event(tags) unless tags.empty?
    end

    if live?
      chat = RubyLLM.chat(model: model_id, provider: provider, assume_model_exists: true)
      chat.with_openui(library, **OpenUI::Rails::StarterLibrary.prompt_options)
      chat.ask(run.prompt) { |chunk| stream.push(chunk.content) if chunk.content.is_a?(String) }
      stream.finish
    else
      canned_chunks.each do |chunk|
        stream.push(chunk)
        sleep(delay)
      end
      stream.finish
    end

    yield OpenUI::Rails::SSE.event(program_tag(stream.text))
    yield OpenUI::Rails::SSE.event(status_tag(stream.result))
  end

  private

  def model_id
    ENV["OPENUI_DEMO_MODEL"].presence || "gpt-4.1-mini"
  end

  def provider
    (ENV["OPENUI_DEMO_PROVIDER"].presence || (ENV["OPENROUTER_API_KEY"].present? ? "openrouter" : "openai")).to_sym
  end

  def delay
    Rails.env.test? ? 0 : 0.12
  end

  # Split mid-token on purpose so the top-down reveal is visible.
  def canned_chunks
    CANNED.scan(/.{1,28}/m)
  end

  def program_tag(text)
    %(<turbo-stream action="update" target="program-#{run.id}"><template>#{ERB::Util.html_escape(text)}</template></turbo-stream>)
  end

  def status_tag(result)
    errors = result.errors.reject(&:warning?).map { |e| "#{e.code}#{e.statement_id ? " (#{e.statement_id})" : ""}" }
    text = errors.empty? ? "Done. #{result.statement_count} statements, no errors." : "Done with errors: #{errors.join(", ")}"
    %(<turbo-stream action="update" target="status-#{run.id}"><template>#{ERB::Util.html_escape(text)}</template></turbo-stream>)
  end
end
