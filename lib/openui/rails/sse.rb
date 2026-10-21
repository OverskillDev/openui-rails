# frozen_string_literal: true

module OpenUI
  module Rails
    # Formats Turbo Stream fragments as Server-Sent Events for a
    # <turbo-stream-source src="..."> element (Turbo connects an EventSource
    # and applies every "message" event's data as turbo-stream HTML). Use
    # with ActionController::Live:
    #
    #   response.headers["Content-Type"] = "text/event-stream"
    #   response.stream.write OpenUI::Rails::SSE.event(tags)
    module SSE
      module_function

      # @param tags [Array<String>, String]
      def event(tags, name: nil, id: nil, retry_ms: nil)
        data = Array(tags).join("\n")
        return "" if data.empty?
        out = +""
        out << "id: #{id}\n" if id
        out << "event: #{name}\n" if name
        out << "retry: #{retry_ms}\n" if retry_ms
        data.split("\n").each { |line| out << "data: #{line}\n" }
        out << "\n"
      end

      def comment(text = "keepalive")
        ": #{text}\n\n"
      end
    end
  end
end
