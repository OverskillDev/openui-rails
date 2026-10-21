# frozen_string_literal: true

require "test_helper"
require "openui/library"

# Byte-for-byte comparison with prompts dumped from @openuidev/lang-core 1.0.1
# (script/golden_prompt.mjs). prompt.md 4.1: the same inputs give identical
# prompts on every platform.
class PromptTest < Minitest::Test
  include OpenUI::TestSupport

  def golden(name)
    File.read(File.join(GOLDEN, name), encoding: "UTF-8")
  end

  def fixture_library
    @fixture_library ||= OpenUI::Library.from_spec(fixture_spec)
  end

  def test_fixture_library_default_prompt_matches_reference
    assert_equal golden("fixture_library_prompt.txt"), fixture_library.prompt
  end

  def test_fixture_library_full_options_prompt_matches_reference
    options = JSON.parse(golden("full_options.json"))
    assert_equal golden("fixture_library_full_prompt.txt"), fixture_library.prompt(**OpenUI::Library::Prompt.normalize_options(options))
  end

  def test_options_accept_snake_case
    text = fixture_library.prompt(preamble: "Custom.", additional_rules: ["Rule one."], edit_mode: true)
    assert text.start_with?("Custom.\n")
    assert_includes text, "## Edit Mode"
    assert text.end_with?("- Rule one.")
  end

  def test_component_groups_render_sections
    lib = OpenUI::Library.define(root: "Stack") do
      component("Stack", description: "Layout") { arg :children, list(component) }
      component("Text", description: "Text") { arg :text, string }
      component("Note", description: "Aside") { arg :text, string }
      group "Layout", components: %w[Stack], notes: ["- Use Stack for columns."]
    end
    text = lib.prompt
    assert_includes text, "### Layout\nStack(children: (Stack | Text | Note)[]) — Layout\n- Use Stack for columns.\n\n### Other\nText(text: string) — Text\nNote(text: string) — Aside"
  end
end
