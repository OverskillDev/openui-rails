# frozen_string_literal: true

require_relative "rails_test_helper"

class CatalogTest < ActionDispatch::IntegrationTest
  CATALOG = OpenUI::Rails::Catalog

  test "every catalog snippet parses and renders without problems" do
    CATALOG.entries.each do |entry|
      result = CATALOG.library.parse(entry.snippet)
      assert_empty result.errors.map(&:to_h), "#{entry.id}: parser errors"
      assert_empty result.unresolved, "#{entry.id}: unresolved references"
      assert_empty result.orphaned, "#{entry.id}: orphaned statements"
      html, problems = CATALOG.render(entry, view_context: ApplicationController.new.view_context)
      assert_empty problems, entry.id
      refute_includes html, "openui-render-error", entry.id
      entry.components.each { |name| assert_includes html, component_hook(name, entry), "#{entry.id}: #{name} not rendered" }
    end
  end

  test "GET /catalog renders every entry grouped by category" do
    get catalog_path
    assert_response :success
    assert_select "[data-catalog-category]", OpenUI::Rails::Catalog::CATEGORIES.length
    assert_equal OpenUI::Rails::Catalog::CATEGORIES, css_select("[data-catalog-category]").map { |s| s["data-catalog-category"] }
    assert_select "article[data-catalog-entry]", CATALOG.entries.length
    CATALOG.entries.each do |entry|
      assert_select "article#entry-#{entry.id}[data-catalog-problems='0']" do
        assert_select "div#catalog-#{entry.id}.openui-root > *", minimum: 1
        assert_equal entry.snippet, css_select("code#snippet-#{entry.id}").first.text
        assert_select "button[data-copy='snippet-#{entry.id}']"
        entry.components.each do |name|
          assert_select "[data-styled-from='#{name}']", text: /#{Regexp.escape(CATALOG.partial_path(name))}/
        end
      end
    end
    assert_select ".catalog-problems", 0
    assert_select ".openui-render-error", 0
    assert_select "button[data-theme-toggle]"
    assert_select "script[src*='tailwindcss']"
    assert_select "link[href*='openui']"
  end

  test "every component in the catalog library appears in at least one entry" do
    shown = CATALOG.entries.flat_map(&:components).uniq
    assert_empty CATALOG.library.component_names - shown
    assert_empty shown - CATALOG.library.component_names
  end

  test "theme param fixes light or dark on the html element" do
    get catalog_path(theme: "dark")
    assert_select "html.dark[data-theme='dark'][data-theme-fixed]"
    get catalog_path(theme: "light")
    assert_select "html[data-theme='light']"
    assert_select "html.dark", 0
    get catalog_path(theme: "<script>")
    assert_select "html[data-theme]", 0
  end

  test "the engine serves the catalog at /openui/catalog only when enabled" do
    get "/openui/catalog"
    assert_response :success
    assert_select "article[data-catalog-entry]", CATALOG.entries.length
    OpenUI::Rails.catalog = false
    get "/openui/catalog"
    assert_response :not_found
    get catalog_path
    assert_response :not_found
  ensure
    OpenUI::Rails.catalog = true
  end

  test "the catalog is off by default" do
    out = `#{RbConfig.ruby} -I#{File.expand_path("../../lib", __dir__)} -e 'require "rails"; require "openui-rails"; print OpenUI::Rails.catalog.inspect' 2>&1`
    assert_equal "false", out
  end

  test "styled-from tokens match the partials and the stylesheet" do
    css = File.read(File.expand_path("../../#{CATALOG::STARTER_CSS}", __dir__))
    helper = File.read(File.expand_path("../../lib/openui/rails/helper.rb", __dir__))
    CATALOG.library.components.each_value do |component|
      style = CATALOG.styled_from(component.name)
      text = style.values_at(:background, :border, :radius, :type, :accent).join(" ")
      if CATALOG.status(component.name) == "starter"
        text.scan(/\.openui-[\w-]+|--openui-[\w-]+/).each do |token|
          assert_includes css, token, "#{component.name}: #{token} not in openui.css"
        end
      else
        source = File.read(File.expand_path("../../#{CATALOG.partial_path(component.name)}", __dir__))
        source += helper if component.name == "Markdown"
        text.split(/[\s,;()]+/).select { |t| t.include?("-") && t.match?(/\A[a-z][\w:\-\/\[\].]*\z/) }.each do |token|
          assert_includes source, token, "#{component.name}: #{token} not in its partial"
        end
      end
    end
  end

  test "CATALOG.md is generated from the catalog and up to date" do
    path = File.expand_path("../../CATALOG.md", __dir__)
    assert_equal "#{CATALOG.markdown}\n", File.read(path), "run bundle exec rake catalog:md"
    CATALOG.library.components.each_value do |component|
      assert_includes File.read(path), "| #{component.name} |"
    end
  end

  private

  # A class only that component's markup carries. A Col inside a Table is drawn by the Table partial.
  def component_hook(name, entry)
    return "openui-table__th" if name == "Col" && entry.components.include?("Table")
    {"Stack" => "openui-stack", "Card" => "openui-card", "Text" => "openui-text", "Table" => "openui-table", "Col" => "openui-col",
     "KeyValue" => "openui-kv", "Callout" => "openui-callout", "Chart" => "openui-chart"}.fetch(name) { "openui-#{name.downcase}" }
  end
end
