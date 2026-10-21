# frozen_string_literal: true

require "erb"

module OpenUI
  module Rails
    # Turns successive ParseResults of a streaming parse into Turbo Stream
    # fragments that update only what changed, keyed by stable DOM ids
    # ("#{mount_id}-#{statement}"), so Hotwire gets the same top-down reveal
    # the React renderer gives. The host picks the transport: ActionCable
    # (Turbo::StreamsChannel.broadcast_stream_to), Server-Sent Events
    # (OpenUI::Rails::SSE with <turbo-stream-source>), or a request response.
    #
    #   progressive = OpenUI::Rails::Progressive.new(library, mount_id: "answer-42")
    #   stream = library.stream_parser(placeholders: true)
    #   stream.on_result { |result, complete| broadcast(progressive.update(result, complete: complete)) }
    class Progressive
      attr_reader :mount_id, :renderer

      def initialize(library, mount_id:, view_context: nil, placeholders: OpenUI::Rails.placeholders)
        @mount_id = mount_id
        @renderer = Renderer.new(library, view_context: view_context, mount_id: mount_id, placeholders: placeholders)
        @last_trace = {}
        @last_root = nil
        @root_id = nil
      end

      # @return [Array<String>] turbo-stream elements (may be empty)
      def update(result, complete: false)
        html = renderer.render(result)
        trace = renderer.trace
        root_id = result.root&.statement_id
        tags = []

        if root_id.nil? || html.empty?
          # Nothing renders yet (or any more): show the mount empty.
          if @last_root && !@last_root.empty?
            tags << turbo_stream("update", mount_id, "")
          end
          @last_root = ""
          @last_trace = {}
          @root_id = nil
          return tags
        end

        if @root_id != root_id || @last_root.nil? || @last_root.empty?
          tags << turbo_stream("update", mount_id, html)
        else
          diff(root_id, trace, tags)
        end
        tags << turbo_stream("update", mount_id, html) if complete && tags.empty? && @last_root != html

        @last_root = html
        @last_trace = trace
        @root_id = root_id
        tags
      end

      # The full tree once more, for a final consistent state.
      def finish(result)
        update(result, complete: true)
      end

      private

      # Replace the smallest set of nodes covering every change: when a node's
      # own markup is unchanged and only descendants moved, descend.
      def diff(sid, trace, tags)
        now = trace[sid]
        before = @last_trace[sid]
        return if now.nil?
        return if before && before.html == now.html
        if before && shape(before, @last_trace) == shape(now, trace)
          now.children.each { |child| diff(child, trace, tags) }
        else
          tags << turbo_stream("replace", renderer.dom_id(sid), now.html)
        end
      end

      # A node's markup with each statement-bound child's markup masked out.
      def shape(node, trace)
        html = node.html.dup
        node.children.each do |child|
          child_html = trace[child]&.html
          html = html.gsub(child_html, "\u0000#{child}\u0000") if child_html && !child_html.empty?
        end
        html
      end

      def turbo_stream(action, target, html)
        %(<turbo-stream action="#{action}" target="#{ERB::Util.html_escape(target)}"><template>#{html}</template></turbo-stream>)
      end
    end
  end
end
