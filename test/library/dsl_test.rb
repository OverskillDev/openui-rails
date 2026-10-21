# frozen_string_literal: true

require "test_helper"
require "openui/library"

class LibraryDslTest < Minitest::Test
  def build
    OpenUI::Library.define(id: "demo", version: "1.0.0", root: "Stack") do
      component "Stack", description: "Lays out children", renders: "openui/components/stack" do
        arg :children, list(component)
        arg :direction, enum("column", "row"), optional: true
      end
      component "Text", description: "A run of text", renders: "openui/components/text" do
        arg :text, string
        arg :variant, enum("body", "heading"), default: "body"
      end
      component "Row", description: "A row of cells" do
        arg :cells, list(object(label: string, value: any, note: optional(string)))
        arg :emphasis, boolean, optional: true
        arg :share, actions("Copy", "OpenUrl"), optional: true
        arg :open, action, optional: true
        arg :query, string, optional: true, binding: true
      end
      function "Percent", description: "Formats part / total as a percentage", returns: string do
        param :part, number
        param :total, number, default: 100
        implement { |part:, total: 100| "#{(part.to_f / total * 100).round(1)}%" }
      end
      action "Copy", description: "Copy text to the clipboard" do
        param :text, string
      end
      group "Layout", components: %w[Stack]
    end
  end

  def test_signatures_follow_prompt_md_5_1
    lib = build
    assert_equal 'Stack(children: (Stack | Text | Row)[], direction?: "column" | "row")', lib.component("Stack").signature(lib)
    assert_equal 'Text(text: string, variant?: "body" | "heading")', lib.component("Text").signature(lib)
    assert_equal "Row(cells: {label: string, value: any, note?: string}[], emphasis?: boolean, share?: @Copy | @OpenUrl, open?: ActionExpression, query?: $binding<string>)",
      lib.component("Row").signature(lib)
    assert_equal "Percent(part: number, total?: number) → string", lib.function("Percent").signature(lib)
    assert_equal "Copy(text: string)", lib.action("Copy").signature(lib)
  end

  def test_json_schema_shape
    schema = build.to_json_schema
    assert_equal %w[Stack Text Row], schema["properties"].keys
    stack = schema["$defs"]["Stack"]
    assert_equal({"type" => "array", "items" => {"anyOf" => [{"$ref" => "#/$defs/Stack"}, {"$ref" => "#/$defs/Text"}, {"$ref" => "#/$defs/Row"}]}}, stack["properties"]["children"])
    assert_equal ["children"], stack["required"]
    assert_equal({"type" => "string", "enum" => %w[body heading], "default" => "body"}, schema["$defs"]["Text"]["properties"]["variant"])
    assert_equal({"$ref" => "#/$defs/ActionExpression"}, schema["$defs"]["Row"]["properties"]["open"])
    assert schema["$defs"].key?("ActionExpression")
    assert_equal "Copy", schema["$defs"]["Copy"]["properties"]["type"]["const"]
    assert_equal({"type" => "string"}, schema["functions"]["Percent"]["returns"])
    assert_equal ["part"], schema["functions"]["Percent"]["params"]["required"]
  end

  def test_spec_round_trip_keeps_prompt_identical
    lib = build
    spec = lib.to_spec
    again = OpenUI::Library.from_spec(JSON.parse(JSON.generate(spec)))
    assert_equal lib.prompt, again.prompt
    assert_equal "demo", again.id
    assert_equal "Stack", again.root
    assert again.component("Row").param("query").bindable
  end

  def test_parse_runs_library_functions_and_leaves_optional_defaults_to_the_renderer
    lib = build
    r = lib.parse("root = Stack([Text(\"hi\"), Text(@Percent(1, 4))])")
    # prompt.md 2.3: a default fills a missing REQUIRED argument; optional ones stay absent.
    assert_nil r.root.props["children"][0].props["variant"]
    assert_equal "25.0%", r.root.props["children"][1].props["text"]
    assert_empty r.errors
  end

  def test_required_after_optional_is_an_error
    assert_raises(OpenUI::Lang::LibraryError) do
      OpenUI::Library.define(root: "A") do
        component("A", description: "a") do
          arg :x, string, optional: true
          arg :y, string
        end
      end
    end
  end

  def test_reserved_names_are_rejected
    %w[Query Mutation Action Count Set].each do |name|
      err = assert_raises(OpenUI::Lang::LibraryError) do
        OpenUI::Library.define { component(name, description: "x") }
      end
      assert_includes err.message, "reserved"
    end
  end

  def test_unknown_root_and_slot_are_rejected
    assert_raises(OpenUI::Lang::LibraryError) { OpenUI::Library.define(root: "Nope") { component("A", description: "a") } }
    assert_raises(OpenUI::Lang::LibraryError) do
      OpenUI::Library.define { component("A", description: "a") { arg :c, component("Missing") } }
    end
  end

  def test_extend_adds_overrides_removes
    base = build
    derived = base.extend do
      component "Badge", description: "A small label", renders: "x", slots: ["Stack.children"] do
        arg :text, string
      end
      override "Text", description: "Plain text", renders: "y" do
        arg :text, string
      end
      remove "Row"
      function "Upper", description: "Upper case", returns: string do
        param :text, string
        implement { |text:| text.upcase }
      end
    end
    assert_nil derived.id, "a derived library does not inherit the base id (prompt.md 2.8)"
    assert_equal "shop", base.extend(id: "shop", version: "2.0.0").id
    assert_equal %w[Stack Text Badge], derived.component_names
    assert_equal "Stack(children: (Stack | Text | Badge)[], direction?: \"column\" | \"row\")", derived.component("Stack").signature(derived)
    assert_equal "Text(text: string)", derived.component("Text").signature(derived)
    assert derived.function("Upper")
    assert_equal %w[Stack Text Row], base.component_names, "base is unchanged"
    assert_raises(OpenUI::Lang::LibraryError) { base.extend { remove "Stack" } }
    assert_raises(OpenUI::Lang::LibraryError) { base.extend { component("Text", description: "dup") } }
  end

  def test_core_loads_without_rails_or_ruby_llm
    out = `#{RbConfig.ruby} -I#{File.expand_path("../../lib", __dir__)} -e 'require "openui"; puts(defined?(Rails).inspect + " " + defined?(RubyLLM).inspect)'`
    assert_equal "nil nil", out.strip
  end
end
