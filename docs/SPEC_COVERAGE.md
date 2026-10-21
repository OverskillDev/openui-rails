# Spec coverage

openui-rails implements [OpenUI Lang 1.0](https://www.openui.com/docs/openui-lang)
as written in `spec/language.md` and `spec/prompt.md` of
[thesysdev/openui](https://github.com/thesysdev/openui) (changelog date
2026-10-12). This page records what is implemented, what is parsed but inert,
and what is missing, against the spec's own conformance fixtures.

## Conformance fixtures (level 1)

`test/conformance/conformance_test.rb` runs every case in
`test/fixtures/openui/1.0` (a copy of `spec/fixtures/1.0`) through the Ruby
parser and compares the canonical result as the fixture README prescribes.
Streaming cases are checked twice: chunk by chunk, and as one batch parse of the
joined chunks.

| Area | Cases | Status |
| --- | --- | --- |
| grammar | 7 | pass |
| entry | 7 | pass |
| streaming | 4 | pass |
| evaluation | 9 | pass |
| state | 5 | pass (level 1 only; see below) |
| actions | 10 | pass (level 1 only; see below) |
| editing | 5 | pass |
| errors | 12 | pass |

Total: 59 cases, 59 pass. There is no known-failure list.

Level 2 (`interactions.json`) replays clicks and typing against a mounted
program. openui-rails v0.1 has no interactive runtime, so those checks do not
run. The level 1 part of each such case (the tree at stream end, including
action plans and bindings) does run and passes.

## Implemented

Language (`language.md`):

- 1 Grammar: fences, comments, identifiers, strings with both quote styles and
  their escape rules, numbers, operators, statements with bracket and ternary
  continuation, the full expression grammar.
- 2 Program model: statement kinds, entry rule with the root-component
  fallback, references and hoisting, cycles, duplicates, orphans.
- 3 Evaluation: JS coercion (`toNumber`, loose equality, truthiness), all
  operators, member access and pluck, every built-in function including
  `@Each`, custom functions with argument checks.
- 4 Streaming: completed-statement watermark, implicit closing, pending never
  overwrites completed, reconciliation when a fence appears, no placeholders
  by default, stream end finalizes the tail (a redefinition in the tail wins,
  which the spec text requires and the reference code does not do).
- 5 State: declarations, auto-declared `$names`, bindings recorded as
  `Binding` values, validation rules (5.4).
- 6 Actions: action plans for built-in steps, `Action([...])`, custom actions,
  one action without a wrapper, legacy action objects in lists. Plans are
  values; nothing runs them.
- 7 Incremental editing: `OpenUI::Lang::Merge.merge_statements`.
- 8 Errors: every parser code with the error object shape and hints;
  `render-error` is produced by the Rails renderer; `runtime-error` by custom
  function failures.

Prompt and spec (`prompt.md`):

- 2 LibrarySpec: `Library#to_spec`, `#to_json_schema`, `Library.from_spec`.
- 3 Rules for libraries: enforced at definition time (reserved names, required
  before optional, root exists).
- 4 Prompt generation: byte-identical to `@openuidev/lang-core` 1.0.1 for the
  fixture library with default options and with tools, bindings, edit mode and
  inline mode on (`test/library/prompt_test.rb`).
- 5 Signatures: generated from the DSL, or regenerated from JSON Schema; the
  regenerated form matches zod's output for all 60+ components of the reference
  chat library spec.
- 7 Message protocol: `OpenUI::Lang::Message.parse` and `.build`.

## Parsed but inert

- `Query` and `Mutation` statements are classified and their arguments kept.
  A reference to a query evaluates to its defaults; a mutation reads as
  `{status: "idle", data: null, error: null}`. No tool is ever called.
- `$variables` hold their declared defaults; nothing writes them.
- Actions produce `OpenUI::Lang::ActionPlan` values. The starter library has no
  component that takes one. A host that registers such a component decides
  what to do with the plan.

## Not implemented

- The interactive runtime: forms, two-way binding, `@Set`/`@Reset`/`@Run`,
  query fetching and refresh, host action events.
- Serialization of a tree back to source (`jsonToOpenUI`, spec 9.2). Programs
  are stored as text, so nothing needs it yet.
- Telemetry, Gateway and Autofix clients, the reference React chat format.

## Extensions

- `limit-exceeded` (source `host`): a cap in `OpenUI::Lang::Limits` was hit.
- `placeholders: true`: unresolved component references stay in the tree as
  `OpenUI::Lang::Placeholder` values for skeleton rendering. Off by default.
