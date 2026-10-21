# Design

Decisions behind openui-rails 0.1, in the order they were made. The spec
documents referenced are `spec/language.md` and `spec/prompt.md` in
thesysdev/openui at the 1.0 release (2026-10-12).

## Goals

- A Rails host can render model-generated UI from OpenUI Lang with its own
  partials and its own design system, with no JavaScript framework.
- The model behaves the same against a Ruby host as against the reference
  React host, which means the same system prompt and the same parse results.
- Nothing the model writes can run code, select a template, or emit markup.
- Small: one gem, no runtime dependencies beyond Rails itself.

## One gem, two layers

The gem is `openui-rails`. Inside it, `lib/openui/lang` and `lib/openui/library`
reference no Rails or RubyLLM constant; `test/library/dsl_test.rb` loads the
core in a subprocess and asserts both are undefined. `lib/openui/rails` and
`lib/openui/ruby_llm` load only when their gems are present.

Why not two gems (`openui_lang` and `openui-rails`) from the start: there is
one consumer, one release cadence, and the split line is already clean. If a
non-Rails host appears, extracting the core is mechanical and the constant
names do not change.

Inside `module OpenUI::Rails` and `module OpenUI::RubyLLM`, bare `Rails` and
`RubyLLM` resolve to the inner modules. The code writes `::Rails` and
`::RubyLLM` everywhere.

## Grammar: all of it

language.md section 10 says a conforming client parses the complete grammar
even for the parts it does not run. The lexer, statement splitter and Pratt
expression parser are direct ports of the reference TypeScript, including the
odd corners (a `-` after a value is subtraction, `a;b` lexes as two names, a
string may hold a raw newline, a multi-line ternary continues a statement).

The test library in `spec/fixtures/1.0/library.json` and the 59 fixture cases
are the parser's test suite. The runner (`test/conformance/conformance_test.rb`)
follows the comparison rules in the fixture README: errors as a multiset,
unresolved and orphans as sets, streaming checked chunk by chunk and as one
batch parse.

## Evaluation: static, one pass

The reference splits materialization (parse time) from evaluation (render
time, reactive). openui-rails has no reactive runtime in 0.1, so
`OpenUI::Lang::Materializer` does both in one pass: references resolve,
arguments map to props and validate, expressions and built-ins evaluate
against the declared state defaults, action calls become `ActionPlan` values.

Two consequences shaped the code:

- Validation skips values that came from expressions, as the reference does
  (an expression is the runtime's business). `Dynamic` wraps such values during
  materialization and is stripped before anything reads them.
- Reachability for orphans follows references, not the evaluated branch of a
  ternary. `entry/006` caught the difference.

Queries, mutations and `$state` are classified and kept so that a program
written for the reference library still parses the same way; a query reference
reads its defaults, exactly what the reference renders before a fetch returns.

One deliberate departure from the reference code: at stream end a pending
redefinition of an earlier name wins, as language.md 2.4 and 4 rule 7 say. The
reference streaming parser discards it. The spec text is normative.

## Streaming equals parsing

`StreamParser` keeps the reference watermark design: completed statements are
parsed once and cached; the tail after the last depth-zero newline is parsed on
every chunk after implicit closing; a fence appearing later resets the cache.
The pending tail has its own byte cap because it is quadratic by nature.

## Placeholders are an option

The task asked for skeletons for references that have not arrived. The spec
(4 rule 5) says no placeholders. Both are available: the default follows the
spec; `placeholders: true` keeps unresolved component references as
`Placeholder` values, only in slots that can hold a component (a `$ref` union,
or an untyped list), never in a scalar prop or a typed data list. The renderer
draws them as `div.openui-pending` with the id the real node will have, so the
later Turbo `replace` targets exactly that element.

## Rendering and DOM ids

Every statement-bound node is wrapped in
`<div id="{mount}-{statement}" class="openui-node" data-openui-statement=...>`.
`.openui-node` is `display: contents`, so wrappers do not affect flex layouts.
Inline components (written directly as an argument) have no wrapper; they
render and update with their statement-bound ancestor.

Optional defaults declared in the library are applied by the renderer, not the
parser, because prompt.md 2.3 only fills a missing required argument. This
keeps parse results identical to the reference while partials still get
`direction: "column"` without a nil check.

A partial that raises is contained: the node renders as an empty marked
element and the renderer records a `render-error` (language.md 8.2).

## Progressive updates

`Progressive` keeps the previous render's per-statement markup and child list
(the renderer records them in `trace`). On each update it walks from the root:
unchanged markup means nothing to send; a node whose own markup (children
masked) is unchanged means descend; otherwise replace that node. The first
appearance of the root is an `update` of the mount. Replacing by id is
idempotent, so a lost or duplicated fragment heals on the next one.

The builder returns fragments and does not pick a transport. Three work today:
ActionCable broadcast, Server-Sent Events into `<turbo-stream-source>` (the
demo; no ActionCable or Redis), and a Turbo Stream response. The host already
has one of these.

## Prompt parity

`OpenUI::Library::Prompt` is a port of `prompt.ts` with the same section order,
the same text and the same option defaults. `script/golden_prompt.mjs` dumps
the reference output for a LibrarySpec; `test/library/prompt_test.rb` compares
byte for byte with default options and with tools, bindings, edit mode and
inline mode on. Signatures come from the DSL types or are regenerated from JSON
Schema; `test/library/spec_test.rb` checks regeneration against zod's output
for the whole reference chat library. Where a spec ships its own signatures
(the fixture library writes `any[]` for some slots), `from_spec` keeps them,
because the prompt the model sees should match the host that wrote the spec.

## RubyLLM surface

`with_openui(library)` is `with_instructions(library.prompt, append: true)`.
Both RubyLLM 1.16 and 2.x accept that call; the 1.x `on_*` callbacks and the
2.x `before_*`/`after_*` callbacks differ, so the integration relies on neither
and reads chunks from the `ask` block. `ask_openui` wraps `ask` with a
`Stream`, which any chunk source can drive. The integration test stubs the
OpenAI Chat Completions SSE endpoint with WebMock and splits statements across
events, so the real `RubyLLM::Chat` path is exercised without a key.

## Limits

`OpenUI::Lang::Limits` caps input bytes, the pending tail, statement count,
bracket depth, string length, rendered elements and `@Each` iterations. A cap
records `limit-exceeded` (source `host`) and stops; nothing raises on model
input. Defaults are generous for a chat answer and small for a denial of
service.

## Testing strategy

| Layer | Test | What it proves |
| --- | --- | --- |
| Parser | conformance fixtures | the spec's own cases, level 1 |
| Parser | `test/lang/*` | caps, encoding, streaming callbacks, message protocol |
| Library | golden prompts, zod signatures, DSL rules, extend, spec round trip | prompt and spec parity |
| Rails | renderer, progressive, SSE, demo integration | HTML, escaping, minimal Turbo fragments, the SSE route |
| RubyLLM | WebMock SSE through `RubyLLM.chat` | instruction injection, events, mid-line chunks |

CI runs Ruby 3.2 and 3.3 against Rails 7.1 and 8.0 (`gemfiles/`). The dummy
app has no database so the matrix has no sqlite3 variance.

## Deferred

Forms, two-way binding, running actions, Query and Mutation against Ruby
tools, serialization back to source, Autofix and Gateway clients, ViewComponent
generator. The parser already classifies and validates all of these so the
prompt can grow without a parser change.
