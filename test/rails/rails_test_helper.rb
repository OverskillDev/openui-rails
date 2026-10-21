# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require "test_helper"
require_relative "../dummy/config/environment"
require "rails/test_help"
require "rails/dom/testing/assertions"

module OpenUI
  module RailsTestSupport
    CANNED = DemoStreamer::CANNED

    def starter
      @starter ||= OpenUI::Rails::StarterLibrary.build
    end

    def view_context
      @view_context ||= ApplicationController.new.view_context
    end

    def render_program(program, placeholders: false, mount_id: "t")
      result = starter.parse(program, placeholders: placeholders, complete: !placeholders)
      renderer = OpenUI::Rails::Renderer.new(starter, view_context: view_context, mount_id: mount_id, placeholders: placeholders)
      [renderer.render(result), renderer, result]
    end

    def doc(html)
      Nokogiri::HTML::DocumentFragment.parse(html)
    end
  end
end
