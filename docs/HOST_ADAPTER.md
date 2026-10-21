# Adapting openui-rails to an existing chat host

A worked example of wiring this gem into a Rails app that already has its own
chat/agent system, rather than starting from the install generator's dummy
app. The scenario: a Rails app with an LLM-backed assistant, its own view
layer for chat messages, and an existing system-prompt strategy. Names below
(`MyApp::Agent`, `MyApp::SystemPrompt`, `app/views/chat/_message.html.erb`)
are illustrative, not a real codebase.

## 1. Registering a library against existing views

Most hosts already have partials or components for the kinds of things OpenUI
Lang renders (a card, a table, a key-value list). Point the library's
`renders:` targets at those instead of the gem's starter partials:

```ruby
module MyAppOpenuiLibrary
  def self.instance
    @instance ||= OpenUI::Library.define(id: "myapp", version: "1.0.0", root: "Stack") do
      component "Card", description: "...", renders: "chat/openui/card" do
        arg :title, string
        arg :children, list(component), optional: true
      end
      # Text, Table, Col, KeyValue, Callout, Chart as in
      # OpenUI::Rails::StarterLibrary, with renders: pointing at your own
      # partials under app/views/chat/openui/.
    end
  end
end
```

Keep the library scoped to what the pilot needs. Leaving out Button, Form,
Image and Link means the model cannot produce anything clickable — useful
while you're still deciding on an interaction story (section 4).

## 2. Where the prompt attaches

If the host builds its model call in two regions — a cached system prompt
that stays byte-identical across turns so the provider's prompt cache hits,
and a per-turn "append" region for anything that varies — `with_openui`'s
default behavior (`with_instructions(append: true)`, adding a second system
message) is usually the wrong place. Call `OpenUI::RubyLLM.instructions_for`
directly and splice the result into the per-turn append region instead:

```ruby
# wherever the host assembles per-turn instructions, flag-gated
def openui_block
  return nil unless my_app_feature_enabled?(:openui, current_team)
  OpenUI::RubyLLM.instructions_for(MyAppOpenuiLibrary.instance, inline_mode: true)
end
```

`inline_mode: true` matters when the assistant's answer is normally prose
plus tool calls: it teaches the model to emit OpenUI Lang in a fenced block
only when a UI is the right answer, and to answer in text otherwise.

Because the prompt is a pure function of a static library, it can later move
into the cached prefix itself (rendered once, checked for staleness in CI)
if the host wants it there from the start instead of paying its cost on
every turn.

## 3. Output channel

Two ways to carry OpenUI Lang programs through an existing chat UI:

**A. A dedicated argument on the tool/action that ends a turn.** If the host's
durable message text already flows through a structured result rather than
streamed content (e.g. a `notify`/`complete` tool call), add an optional
`ui: string` argument, parse it with `library.parse(ui)`, and store the
validated program as a message segment alongside the prose. Render it with
`openui_render` next to the existing markdown rendering. This keeps the
prose channel untouched and makes every rendered program a persisted,
replayable artifact — the trade-off is no token-by-token reveal; the program
arrives whole when the tool call completes.

**B. The content stream.** Parse fenced `openui` blocks out of streamed
content as they arrive, and drive `OpenUI::Rails::Progressive` to broadcast
statements into a slot in the in-flight message. This gives a top-down reveal
but needs the host's streaming layer to treat part of its "transient
narration" channel as durable, plus persistence of the final program at
round end.

Start with whichever channel already carries durable text in the host; move
to streaming later if the reveal matters more than channel purity.

## 4. Actions stay out of the pilot

Nothing about an existing approval/permission system needs to change for a
read-only pilot: the parser only instantiates registered components, and a
pilot library with no Button/Form/Link/action component has no code path
from a rendered program back into a tool call. When actions are added later
(`@ToAssistant(...)` clicks becoming the next turn), they re-enter whatever
dispatch and gating the host already has for user-initiated turns — the
gem's interaction hook is a stub by design until that mapping exists.

## 5. Rollout shape

- Gate by a feature flag, scoped to the surfaces you're piloting (a report
  generator, a digest, anything with naturally tabular output) rather than
  every chat.
- Track parse outcomes per turn (`result.errors`, `result.fatal?`) to see how
  often the model writes a program that actually renders.
- On a fatal parse, fall back to the prose answer — the user sees what they'd
  see without the pilot.
- Before widening exposure, check how your model of choice does against
  OpenUI's own conformance fixtures; model-to-model variance in Lang output
  quality is real and worth measuring before relying on it in production.
