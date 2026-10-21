# frozen_string_literal: true

require "test_helper"
require "openui/library"

# Signature regeneration from JSON Schema (prompt.md 2.4) against the spec of
# the reference React chat library, which zod generated.
class SpecSignatureTest < Minitest::Test
  include OpenUI::TestSupport

  def chat_spec
    @chat_spec ||= JSON.parse(File.read(File.join(GOLDEN, "chat_library.spec.json"), encoding: "UTF-8"))
  end

  def test_regenerated_signatures_match_zod_output
    lib = OpenUI::Library.from_spec(chat_spec)
    mismatches = []
    lib.components.each_value do |c|
      given = c.signature_override
      regenerated = "#{c.name}(#{c.params.map { |p| p.signature(lib) }.join(", ")})"
      mismatches << [c.name, given, regenerated] if given != regenerated
    end
    message = mismatches.map { |n, g, r| "#{n}\n  given: #{g}\n  regen: #{r}" }.join("\n")
    assert_empty mismatches, message
  end

  def test_fixture_library_prompt_uses_given_signatures
    lib = OpenUI::Library.from_spec(fixture_spec)
    assert_equal fixture_spec["components"]["Stack"]["signature"], lib.component("Stack").signature(lib)
    assert lib.component("Input").param("value").bindable
    assert lib.function("Upper")
    assert lib.action("CopyToClipboard")
    assert_equal "Stack", lib.root
  end
end
