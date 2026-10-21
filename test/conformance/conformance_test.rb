# frozen_string_literal: true

require "test_helper"

# Runs the spec/fixtures/1.0 conformance cases (language.md Appendix B, rules
# in test/fixtures/openui/1.0/README.md) at level 1: program, streaming,
# editing and validation checks. Level 2 (interactions.json) needs a renderer
# that runs actions, which openui-rails v0.1 does not have; those cases still
# run their level 1 check.
class ConformanceTest < Minitest::Test
  include OpenUI::TestSupport

  FIXTURES = OpenUI::TestSupport::OPENUI_FIXTURES
  AREAS = %w[grammar entry streaming evaluation state actions editing errors].freeze

  # Cases this implementation knowingly fails, with the reason.
  KNOWN_FAILURES = {}.freeze

  def self.cases
    AREAS.flat_map do |area|
      dir = File.join(FIXTURES, area)
      next [] unless File.directory?(dir)
      Dir.children(dir).select { |c| File.directory?(File.join(dir, c)) }.sort.map { |c| [area, c] }
    end
  end

  # ── Summary (README, "How the tree is summarized") ──

  def action_params
    @action_params ||= (fixture_spec.dig("schema", "actions") || {}).to_h { |n, a| [n, (a.dig("params", "properties") || {}).keys] }
  end

  def summarize_action(step)
    d = step.data
    case step.type
    when :continue_conversation
      {"action" => "ToAssistant", "args" => d[:context].nil? ? [d[:message]] : [d[:message], d[:context]]}
    when :open_url then {"action" => "OpenUrl", "args" => [d[:url]]}
    when :set then {"action" => "Set", "args" => [d[:target], d[:value]]}
    when :reset then {"action" => "Reset", "args" => d[:targets]}
    when :run then {"action" => "Run", "args" => [d[:statement_id]]}
    when :custom_action
      keys = action_params[d[:name]] || d[:params].keys
      {"action" => d[:name], "args" => keys.map { |k| summarize(d[:params][k]) }}
    end
  end

  def summarize(v)
    case v
    when nil then nil
    when OpenUI::Lang::Element
      props = v.props.map { |k, pv| [k, summarize(pv)] }.reject { |(_, s)| s.nil? }.to_h
      {"type" => v.type, "props" => props}
    when OpenUI::Lang::ActionPlan then {"actions" => v.steps.map { |s| summarize_action(s) }}
    when OpenUI::Lang::Binding then {"$binding" => v.name}
    when Array then v.map { |x| summarize(x) }
    when Hash then v.transform_values { |x| summarize(x) }
    else v
    end
  end

  def json(v)
    JSON.parse(JSON.generate(v))
  end

  def canonical(result)
    {
      "root" => json(summarize(result.root)),
      "errors" => result.errors.map { |e| {"code" => e.code, "statementId" => e.statement_id}.compact },
      "errorObjects" => result.errors.map { |e| e.to_h },
      "unresolved" => result.unresolved,
      "orphans" => result.orphaned,
      "incomplete" => result.incomplete,
      "state" => json(result.state)
    }
  end

  # ── Comparison (README, "Comparison") ──

  def claims(expected, actual)
    pool = actual.dup
    expected.sort_by { |e| -e.keys.length }.all? do |e|
      i = pool.index { |a| e.all? { |k, v| json(v) == json(a[k]) } }
      i && pool.delete_at(i)
    end
  end

  def compare(key, want, got)
    case key
    when "errors" then want.length == got.length && claims(want, got)
    when "errorObjects" then claims(want, got)
    when "unresolved", "orphans" then want.uniq.sort == got.uniq.sort
    else json(want) == json(got)
    end
  end

  def assert_canonical(expected, actual, label)
    expected.each do |key, want|
      next if key == "statements"
      got = actual[key]
      assert compare(key, want, got), "#{label}: #{key}\n  expected: #{JSON.pretty_generate(want)}\n  actual:   #{JSON.pretty_generate(got)}"
    end
  end

  def read(area, name, file)
    File.read(File.join(FIXTURES, area, name, file), encoding: "UTF-8")
  end

  def exist?(area, name, file)
    File.exist?(File.join(FIXTURES, area, name, file))
  end

  def run_program(text)
    canonical(fixture_parser.parse(text))
  end

  cases.each do |area, name|
    define_method("test_#{area}_#{name.tr("-", "_")}") do
      label = "#{area}/#{name}"
      skip KNOWN_FAILURES[label] if KNOWN_FAILURES[label]

      if exist?(area, name, "validation.json")
        JSON.parse(read(area, name, "validation.json"))["cases"].each do |c|
          assert_equal c["valid"], OpenUI::Lang::FormValidation.valid?(c["value"], c["rules"]),
            "#{label}: rules=#{c["rules"].inspect} value=#{c["value"].inspect}"
        end
        return
      end

      expected = JSON.parse(read(area, name, "expected.json"))

      if exist?(area, name, "chunks.json")
        chunks = JSON.parse(read(area, name, "chunks.json"))
        sp = fixture_stream_parser
        chunks.each { |c| sp.push(c) }
        assert_canonical(expected, canonical(sp.finish), "#{label} (streamed)")
        assert_canonical(expected, run_program(chunks.join), "#{label} (batch)")
        return
      end

      input = read(area, name, "input.oui")
      if exist?(area, name, "patch.oui")
        merged = OpenUI::Lang::Merge.merge_statements(input, read(area, name, "patch.oui"))
        statements = merged.lines.filter_map { |l| l[/\A(\$?\w+) =/, 1] }
        assert_equal expected["statements"], statements, "#{label}: statements" if expected.key?("statements")
        assert_canonical(expected, run_program(merged), label)
        return
      end

      assert_canonical(expected, run_program(input), label)
    end
  end
end
