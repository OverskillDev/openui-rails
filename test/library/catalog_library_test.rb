# frozen_string_literal: true

require_relative "../rails/rails_test_helper"

# The catalog library is the starter library plus the components the catalog
# page shows. Every added component must reach the model through the prompt.
class CatalogLibraryTest < ActiveSupport::TestCase
  ADDED = %w[Section Divider Markdown Metric Badge List Checklist Timeline Form Input Select Checkbox Button Image Avatar].freeze

  def library
    @library ||= OpenUI::Rails::CatalogLibrary.build
  end

  test "adds the catalog components to the starter library" do
    assert_equal ADDED, OpenUI::Rails::CatalogLibrary.added_components
    assert_equal OpenUI::Rails::StarterLibrary.build.component_names + ADDED, library.component_names
    assert_equal "openui-catalog", library.id
    assert_equal "Stack", library.root
  end

  test "the prompt includes every component's signature and description" do
    prompt = library.prompt(**OpenUI::Rails::CatalogLibrary.prompt_options)
    library.components.each_value do |component|
      assert_includes prompt, "#{component.signature(library)} — #{component.description}", "#{component.name} missing from the prompt"
    end
    %w[Structure Rich\ text Status Forms\ and\ actions Media].each { |group| assert_includes prompt, "### #{group}\n" }
  end

  test "container slots accept the added components" do
    sig = library.component("Stack").signature(library)
    ADDED.each { |name| assert_includes sig, name }
    assert_includes library.component("Button").signature(library), "action?: ActionExpression"
  end

  test "every component renders through a partial that exists" do
    library.components.each_value do |component|
      path = File.expand_path("../../app/views/#{component.renders.sub(%r{/([^/]+)\z}, '/_\1')}.html.erb", __dir__)
      assert File.exist?(path), "#{component.name}: no partial at #{path}"
    end
  end

  test "the spec round trip keeps the prompt identical" do
    again = OpenUI::Library.from_spec(JSON.parse(JSON.generate(library.to_spec)))
    assert_equal library.prompt, again.prompt
  end

  test "the starter library is unchanged by the catalog" do
    starter = OpenUI::Rails::StarterLibrary.build
    assert_equal %w[Stack Card Text Table Col KeyValue Callout Chart], starter.component_names
    refute_includes starter.prompt, "Button("
  end
end
