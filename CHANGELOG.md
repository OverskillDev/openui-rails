# Changelog

## 0.1.1 (2026-10-21)

- Catalog: `OpenUI::Rails::CatalogLibrary` (starter plus 15 Tailwind
  components: Section, Divider, Markdown, Metric, Badge, List, Checklist,
  Timeline, Form, Input, Select, Checkbox, Button, Image, Avatar), a catalog
  page (`/openui/catalog` behind `OpenUI::Rails.catalog`, `/catalog` in the
  dummy app), CATALOG.md and `rake catalog:md`.
- Chart: `pie` variant. Col: optional `sort` hint shown in the Table header.
- Fix: line charts rendered as filled polygons.
- `openui_icon`, `openui_markdown`, `openui_safe_src` view helpers.

## 0.1.0 (tagged 2026-10-16, not published)

First release. OpenUI Lang 1.0 (2026-10-12) for Rails.

- Parser: lexer, expressions, statements, batch and streaming parse, static
  evaluation of expressions and built-in functions, schema validation with the
  spec's error codes, message protocol, edit merge, form validation rules,
  host limits. 59 of 59 level-1 conformance fixtures pass.
- Library DSL with LibrarySpec read/write and a prompt generator that matches
  the reference generator byte for byte.
- Rails: ERB renderer, starter components (Stack, Card, Text, Table, Col,
  KeyValue, Callout, Chart), Turbo Stream progressive updates, SSE helper,
  view helpers, install generator.
- RubyLLM: `with_openui`, `ask_openui`, `on_openui_event`, `OpenUI::RubyLLM::Stream`.
- Not in this release: running Query/Mutation, reactive state, forms,
  actions, Autofix/Gateway, ViewComponent generator.
