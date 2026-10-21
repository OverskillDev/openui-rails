# openui-rails

[OpenUI Lang](https://www.openui.com/docs/openui-lang) for Rails and Hotwire,
with a [RubyLLM](https://rubyllm.com) hook.

The model answers in OpenUI Lang, a line-oriented language for generative UI
(`title = Text("Hello", "heading")`). This gem parses it against a component
library you define in Ruby, renders each component with an ERB partial, and
updates the page with Turbo Streams as statements arrive. The system prompt is
generated from the library, so adding a component is one Ruby block and nothing
else.

Status: 0.1.1, not yet on rubygems.org. Implements spec 1.0 (2026-10-12).
Ruby 3.2 or later, Rails 7.1 or later, tested with Propshaft (the Sprockets
path is wired but untested). RubyLLM 1.16 or 2.x, optional.

## What you get

- `OpenUI::Lang`: a parser for the full 1.0 grammar, streaming and batch, with
  the spec's validation and error codes. All 59 level-1 conformance fixtures
  from the spec repository pass. Expressions and built-in functions are
  evaluated statically; queries, mutations and actions are parsed and left
  inert (see [docs/SPEC_COVERAGE.md](docs/SPEC_COVERAGE.md)).
- `OpenUI::Library`: a DSL for components with typed positional arguments, a
  LibrarySpec reader and writer, and a prompt generator that produces the same
  bytes as the reference `@openuidev/lang-core` generator.
- `OpenUI::Rails`: an ERB renderer, eight starter components with light and
  dark styles, a catalog library of 15 more (Tailwind partials) with a
  browsable catalog page, a progressive Turbo Stream builder, an SSE
  formatter, view helpers and an install generator.
- `OpenUI::RubyLLM`: `chat.with_openui(library)` injects the prompt,
  `chat.ask_openui(prompt)` streams and parses the answer.

## Quick start

```sh
bundle add openui-rails
bin/rails generate openui:install
```

The generator writes `config/initializers/openui.rb` and
`app/libraries/openui_library.rb`. The library starts from the starter
components and extends them:

```ruby
# app/libraries/openui_library.rb
module OpenuiLibrary
  def self.instance
    @instance ||= OpenUI::Rails::StarterLibrary.build.extend(id: "myapp", version: "1.0.0") do
      component "Metric", description: "One number with a label, for KPIs.",
        renders: "openui/components/metric", slots: ["Stack.children", "Card.children"] do
        arg :label, string
        arg :value, number
        arg :unit, string, optional: true
      end
    end
  end
end
```

```erb
<%# app/views/openui/components/_metric.html.erb %>
<%# locals: (openui:, element:, label:, value:, unit: nil) %>
<div class="metric">
  <span class="metric__value"><%= openui.text(value) %><%= unit %></span>
  <span class="metric__label"><%= openui.text(label) %></span>
</div>
```

One controller action, no streaming:

```ruby
class AnswersController < ApplicationController
  def create
    chat = RubyLLM.chat.with_openui(OpenuiLibrary.instance, **OpenuiLibrary.prompt_options)
    @response = chat.ask_openui(params[:question])
  end
end
```

```erb
<%= openui_stylesheet_tag %>
<%= openui_render(@response.result, library: OpenuiLibrary.instance, mount_id: "answer") %>
```

`@response.result` is an `OpenUI::Lang::ParseResult`; `@response.program` is
the OpenUI Lang text the model wrote, which is what you store.

## How it works

1. `library.prompt` turns the component definitions into the system prompt
   (syntax rules, one signature line per component, streaming guidance).
2. The model writes statements such as `root = Stack([title, table])`,
   `title = Text("Plans", "heading")`, one per line, references allowed before
   definition.
3. `OpenUI::Lang::StreamParser` parses after every chunk. Completed statements
   are parsed once; the unfinished tail is closed implicitly and parsed again.
   Unknown components and invalid arguments are dropped and reported; the rest
   renders.
4. `OpenUI::Rails::Renderer` walks the tree and renders each component with the
   partial the library names for it. Every statement-bound node gets a stable
   DOM id.
5. `OpenUI::Rails::Progressive` compares consecutive renders and emits Turbo
   Stream fragments for the smallest changed nodes.

## The language

OpenUI Lang is specified by Thesys in
[spec/language.md](https://github.com/thesysdev/openui/blob/main/spec/language.md)
and [spec/prompt.md](https://github.com/thesysdev/openui/blob/main/spec/prompt.md)
of the thesysdev/openui repository (MIT). This gem follows those documents; the
summary below is for orientation and the spec wins where they differ.

- A program is lines of `name = expression`. Lines without that shape are
  skipped. `//` and `#` start comments. Code inside triple-backtick fences is
  used and prose around it ignored.
- Expressions: strings (`"..."` with JSON escapes, or `'...'`), numbers,
  `true`, `false`, `null`, arrays `[a, b]`, objects `{key: value}`, references
  to other statements, and component calls `Name(arg1, arg2)`. Operators,
  ternaries, member access and `@` functions (`@Count`, `@Sum`, `@Filter`,
  `@Each`, ...) are evaluated.
- Arguments are positional, in the order the library declares them. Optional
  arguments can be left off the end; `null` skips one.
- `root` is the entry. Without it, the first statement that calls the library's
  root component renders with a `no-root` warning.
- References may point forward. Unresolved references render nothing and are
  listed in the result; a cycle counts as unresolved at the point it closes.
- A mistake removes the smallest unit: an invalid optional argument is dropped,
  a component missing a required argument is dropped, a line that is not a
  statement is skipped. Each removal is an error with a code and a hint.
- Streaming equals parsing: the result after the last chunk is the same as a
  batch parse of the whole text.

`OpenUI::Lang::Message` reads and writes the storage format
(`]]>openui:content` ... `]]>openui:end`). `OpenUI::Lang::Merge` applies an
edit-mode patch.

## Defining components

```ruby
library = OpenUI::Library.define(id: "support", version: "1.2.0", root: "Stack") do
  component "Stack", description: "Lays out children.", renders: "openui/components/stack" do
    arg :children, list(component)                  # any component in the library
    arg :direction, enum("column", "row"), default: "column"
  end

  component "Table", description: "A table built from columns.", renders: "openui/components/table" do
    arg :columns, list(component("Col"))            # only Col
    arg :caption, string, optional: true
  end

  function "Percent", description: "Formats part / total as a percentage.", returns: string do
    param :part, number
    param :total, number, default: 100
    implement { |part:, total: 100| format("%.1f%%", part.to_f / total * 100) }
  end

  group "Data", components: %w[Table Col], notes: ["- Define each Col as its own statement."]
end
```

| Type | Signature in the prompt | JSON Schema |
| --- | --- | --- |
| `string`, `number`, `boolean`, `any` | `string` | `{"type": "string"}` |
| `enum("a", "b")` | `"a" \| "b"` | `enum` |
| `list(type)` | `T[]`, or `(A \| B)[]` for unions | `array` |
| `object(label: string, note: optional(string))` | `{label: string, note?: string}` | `object` |
| `component`, `component("Card", "Text")` | `Card \| Text` | `$ref` or `anyOf` |
| `action`, `actions("Copy", "OpenUrl")` | `ActionExpression`, `@Copy \| @OpenUrl` | `$ref` |
| `arg ..., binding: true` | `$binding<T>` | unchanged |

Rules checked when the library is built: names start with an uppercase letter
and avoid the reserved names (`Query`, `Mutation`, `Action`, the built-ins),
required arguments come before optional ones, the root exists, slots name
existing components.

`renders:` takes a partial path, a proc receiving the locals, or a class whose
instances respond to `render_in` (a ViewComponent). Partials receive each
argument as a local plus `openui` (the renderer) and `element`. Call
`openui.node(value)` for child components and `openui.text(value)` for scalars.

`library.extend(id:, version:) { ... }` derives a library: `component` adds
(with `slots:` to join parent unions), `override` replaces, `remove` deletes,
`function` and `action` add. A derived library does not inherit the base's
id, so name it. `library.to_spec` writes the LibrarySpec document;
`OpenUI::Library.from_spec` reads one, including specs produced by the
reference CLI.

## Rendering

```ruby
result = library.parse(program)                       # OpenUI::Lang::ParseResult
result.root                                           # OpenUI::Lang::Element or nil
result.errors.map(&:to_h)                             # spec error objects, with hints
html = OpenUI::Rails::Renderer.new(library, view_context: view_context, mount_id: "answer").render(result)
```

In views, `openui_render(program_or_result, library:, mount_id:)` wraps the tree
in a `div.openui-root`; `openui_mount(id)` renders an empty mount for a
response that will stream in. Override any starter partial by creating the same
path under your own `app/views/openui/components/`, or pass `--partials` to the
generator to copy them (it copies the catalog partials too).

Placeholders: the spec renders nothing for a reference that has not arrived.
Pass `placeholders: true` (or set `OpenUI::Rails.placeholders = true`) to keep
unresolved component references as skeleton nodes with their final DOM id, so a
later statement replaces exactly that node.

## Streaming with Turbo

```ruby
progressive = OpenUI::Rails::Progressive.new(library, mount_id: "answer-#{message.id}", placeholders: true)
stream = OpenUI::RubyLLM::Stream.new(library, placeholders: true)
stream.on_event do |event|
  next unless event.type == :result
  tags = progressive.update(event.result, complete: event.complete)
  Turbo::StreamsChannel.broadcast_stream_to("chat_#{chat.id}", content: tags.join) unless tags.empty?
end
chat.ask(prompt) { |chunk| stream.push(chunk.content) if chunk.content }
stream.finish
```

`progressive.update` returns `<turbo-stream>` fragments: an `update` of the
mount when the root first appears, then `replace` of the nearest changed node.
Send them over whatever you have: ActionCable as above, a
`<turbo-stream-source src="/answers/1/events">` fed by
`OpenUI::Rails::SSE.event(tags)` from an `ActionController::Live` action (the
demo app does this, no ActionCable or Redis), or a Turbo Stream response.

## RubyLLM

```ruby
chat = RubyLLM.chat(model: "gpt-4.1-mini")
chat.with_openui(library, additional_rules: ["Use Table for comparisons."])  # appends a system message
response = chat.ask_openui("Compare these 3 plans") do |event|
  # event.type: :chunk, :statement, :result (event.result, event.complete), :end
end
response.result     # ParseResult at stream end
response.program    # the OpenUI Lang text
response.message    # the RubyLLM::Message
```

`with_openui` calls `with_instructions(library.prompt, append: true)`; pass
`append: false` to replace existing instructions, or `instructions_options:`
for RubyLLM options such as `persist: false`. On an `acts_as_chat` record the
system message is persisted like any instruction. `chat.on_openui_event { }`
registers handlers for every later `ask_openui`. `OpenUI::RubyLLM.instructions_for(library)`
returns the prompt text for hosts that assemble prompts themselves.

The hook installs itself when `openui/ruby_llm` is required (the Rails engine
does this after initialization when RubyLLM is loaded).

## Security model

Model output is data, never code.

- The renderer instantiates registered components only. An unknown component
  is dropped by the parser with an `unknown-component` error.
- Partial paths and renderer classes come from the library definition; nothing
  in the program text selects a template.
- All argument values are escaped by ERB or `openui.text`. The renderer never
  marks model text `html_safe`. The starter components have no raw HTML,
  links, images, forms or buttons. The catalog library adds form controls
  and buttons that render inert, Markdown that escapes before adding a fixed
  set of tags (no links), and Image/Avatar that load only `https://` or
  host-relative sources.
- Actions are parsed into plan values and never executed. A host that wants
  buttons registers its own component and decides what a plan means.
- `OpenUI::Lang::Limits` caps input bytes (256 KiB), the re-parsed streaming
  tail (64 KiB), statements (2,000), bracket depth (64), string length
  (32 KiB), rendered elements (10,000) and `@Each` iterations (1,000). Hitting
  a cap stops parsing with a `limit-exceeded` error; nothing raises.
- A partial that raises is contained: the node renders as an empty
  `div.openui-render-error` and the renderer records a `render-error`.
- Library functions run Ruby you wrote, with arguments checked against their
  declared types first.

## Demo

`test/dummy` is a Rails app without a database. Run it with:

```sh
bundle install
cd test/dummy && bundle exec puma -p 3000 config.ru
```

`/demo` asks a question and streams the answer over SSE into Turbo. Without an
API key it replays a canned answer in small chunks; with `OPENAI_API_KEY` or
`OPENROUTER_API_KEY` set (and optionally `OPENUI_DEMO_MODEL`,
`OPENUI_DEMO_PROVIDER`) it asks a model. `/sample` renders the canned program
in one pass. `/catalog` is the component catalog (below).

## Catalog

`OpenUI::Rails::CatalogLibrary.build` is the starter library plus Section,
Divider, Markdown, Metric, Badge, List, Checklist, Timeline, Form, Input,
Select, Checkbox, Button, Image and Avatar. Their partials use plain Tailwind
utility classes with `dark:` variants, so a host that renders them needs
Tailwind to scan the gem's views (Tailwind 4: `@source` the path from
`bundle show openui-rails` plus `/app/views`). Buttons and form controls are
inert; a Button's action plan is in `data-openui-action` for the host to wire.

The catalog page shows every component as an OpenUI Lang snippet rendered by
the parser and renderer, with its source, when an agent would use it, and the
partial and classes it is styled from. In the dummy app it is `/catalog`. In a
host:

```ruby
# config/routes.rb
mount OpenUI::Rails::Engine, at: "/openui"   # GET /openui/catalog
# config/initializers/openui.rb
OpenUI::Rails.catalog = Rails.env.development?   # off by default; 404 when off
```

The page loads Tailwind from the Play CDN and uses inline scripts (with the CSP
nonce when one is configured). Host overrides of component partials show up in
the catalog, since partials resolve from the host first.
[CATALOG.md](CATALOG.md) is the index of every component with its signature,
arguments, status and styling; regenerate it with `bundle exec rake catalog:md`.

## Prior art

Checked on 2026-10-16 before writing any code:

- rubygems.org: `openui`, `openui_lang`, `openui-lang`, `openui-rails`,
  `openui_rails` and `open_ui` do not exist. Searches for `generative_ui` and
  `genui` found two adjacent gems, neither for OpenUI Lang:
  [`generative_ui`](https://github.com/kryzhovnik/generative_ui) 0.1.0 (a
  RubyLLM tool-call catalog with an A2UI-shaped JSON tree, rendered with
  partials or ViewComponent) and
  [`a2ui-rails`](https://github.com/vicentereig/a2ui-rails) 0.1.0 (Google's
  A2UI over DSPy.rb and Turbo Streams).
- GitHub: no Ruby or Rails implementation of OpenUI Lang. Ports exist for
  Flutter (two), Rust (`openui-rs`), MoonBit, and a Python integration for
  Hermes Agent; Thesys ships an Open WebUI plugin.
- Thesys' first-party runtimes are React, Vue, Svelte and Angular, with React
  Native, React Email and A2UI bridges in the same monorepo. The
  [State of Generative UI report](https://www.openui.com/blog/state-of-generative-ui-report)
  lists React, Vue, Svelte, React Native and React Email as renderers. None
  render on the server.

## Roadmap

- Forms and actions with a host-side interaction hook, then `@ToAssistant` as
  the next user turn.
- `Query` and `Mutation` against Ruby tools, with refresh.
- Autofix and Gateway compatibility (the LibrarySpec is already the input they
  take).
- A ViewComponent generator for component classes.
- Serialization of a tree back to source for edit mode round trips.

## Development

```sh
bundle install
bundle exec rake test                       # Rails 8.0 (Gemfile)
BUNDLE_GEMFILE=gemfiles/rails_7.1.gemfile bundle exec rake test
```

The golden prompts in `test/fixtures/golden/` come from the reference
generator; regenerate them with `script/golden_prompt.mjs` after building
`packages/lang-core` in a checkout of thesysdev/openui. The conformance
fixtures are a copy of `spec/fixtures/1.0`; refresh them from the same
checkout.

Design notes are in [docs/DESIGN.md](docs/DESIGN.md).

## License

MIT, see [LICENSE](LICENSE). The parser and prompt generator are ports of
thesysdev/openui (MIT, Thesys Inc.) and the conformance fixtures are copied
from it; see [NOTICE](NOTICE).
