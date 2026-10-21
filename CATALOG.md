# Component catalog

Every component an agent can use with `OpenUI::Rails::CatalogLibrary`, generated from
`lib/openui/rails/catalog.rb` by `bundle exec rake catalog:md`; do not edit by hand.
The live page is `/catalog` in the dummy app (`cd test/dummy && bundle exec puma -p 3530 config.ru`),
or `/openui/catalog` in a host that mounts the engine and sets `OpenUI::Rails.catalog = true`.

- **starter**: in `OpenUI::Rails::StarterLibrary`, styled by `app/assets/stylesheets/openui.css` (classes and `--openui-*` variables).
- **added-in-catalog**: added by `OpenUI::Rails::CatalogLibrary`, styled with Tailwind utility classes in the partial.
  A host that renders these needs Tailwind to scan the gem's views, for example in Tailwind 4:
  `@source "<path from bundle show openui-rails>/app/views";`.

Arguments are positional, in the order shown; `?` marks optional ones. `Component[]` stands for a
slot that takes any component in the library; the prompt spells it out as the full union.
Chart's `pie` variant and Col's `sort` hint are recent additions to the starter components.

## Components

| Component | Category | Status | OpenUI Lang signature | Partial |
| --- | --- | --- | --- | --- |
| Stack | Layout | starter | `Stack(children: Component[], direction?: "column" \| "row")` | `app/views/openui/components/_stack.html.erb` |
| Card | Layout | starter | `Card(title: string, children?: Component[], subtitle?: string)` | `app/views/openui/components/_card.html.erb` |
| Text | Text | starter | `Text(text: string, variant?: "body" \| "heading" \| "caption")` | `app/views/openui/components/_text.html.erb` |
| Table | Data | starter | `Table(columns: Col[], caption?: string)` | `app/views/openui/components/_table.html.erb` |
| Col | Layout | starter | `Col(label: string, data: any[], align?: "left" \| "right", sort?: "asc" \| "desc")` | `app/views/openui/components/_col.html.erb` |
| KeyValue | Data | starter | `KeyValue(items: {label: string, value: any}[], title?: string)` | `app/views/openui/components/_key_value.html.erb` |
| Callout | Text | starter | `Callout(text: string, variant?: "info" \| "tip" \| "warning" \| "danger", title?: string)` | `app/views/openui/components/_callout.html.erb` |
| Chart | Charts | starter | `Chart(labels: string[], series: {name: string, data: number[]}[], variant?: "bar" \| "line" \| "pie", title?: string)` | `app/views/openui/components/_chart.html.erb` |
| Section | Layout | added-in-catalog | `Section(title: string, children: Component[], description?: string)` | `app/views/openui/components/_section.html.erb` |
| Divider | Layout | added-in-catalog | `Divider(label?: string)` | `app/views/openui/components/_divider.html.erb` |
| Markdown | Text | added-in-catalog | `Markdown(text: string)` | `app/views/openui/components/_markdown.html.erb` |
| Metric | Data | added-in-catalog | `Metric(label: string, value: number, unit?: string, delta?: number, caption?: string)` | `app/views/openui/components/_metric.html.erb` |
| Badge | Data | added-in-catalog | `Badge(text: string, tone?: "neutral" \| "info" \| "success" \| "warning" \| "danger")` | `app/views/openui/components/_badge.html.erb` |
| List | Lists | added-in-catalog | `List(items: string[], variant?: "bullet" \| "ordered")` | `app/views/openui/components/_list.html.erb` |
| Checklist | Lists | added-in-catalog | `Checklist(items: {label: string, done?: boolean}[], title?: string)` | `app/views/openui/components/_checklist.html.erb` |
| Timeline | Lists | added-in-catalog | `Timeline(items: {title: string, time?: string, text?: string}[])` | `app/views/openui/components/_timeline.html.erb` |
| Form | Forms and inputs | added-in-catalog | `Form(name: string, children: Component[], title?: string)` | `app/views/openui/components/_form.html.erb` |
| Input | Forms and inputs | added-in-catalog | `Input(name: string, label?: string, placeholder?: string, type?: "text" \| "email" \| "number" \| "date" \| "textarea", value?: string)` | `app/views/openui/components/_input.html.erb` |
| Select | Forms and inputs | added-in-catalog | `Select(name: string, options: string[], label?: string, value?: string)` | `app/views/openui/components/_select.html.erb` |
| Checkbox | Forms and inputs | added-in-catalog | `Checkbox(name: string, label: string, checked?: boolean)` | `app/views/openui/components/_checkbox.html.erb` |
| Button | Forms and inputs | added-in-catalog | `Button(label: string, action?: ActionExpression, variant?: "primary" \| "secondary" \| "ghost")` | `app/views/openui/components/_button.html.erb` |
| Image | Media | added-in-catalog | `Image(alt: string, src?: string, caption?: string)` | `app/views/openui/components/_image.html.erb` |
| Avatar | Media | added-in-catalog | `Avatar(name: string, subtitle?: string, src?: string)` | `app/views/openui/components/_avatar.html.erb` |

## Arguments and styling

### Stack

Lays out children top to bottom (column, the default) or side by side (row).

- `children`: `Component[]`
- `direction`: `"column" \| "row"` (optional, default "column")

Styled from `app/views/openui/components/_stack.html.erb` + `app/assets/stylesheets/openui.css`:

- background: none
- border: none
- radius: none
- typography: inherits .openui-root (15px system-ui)
- accent: none
- note: .openui-stack gap: var(--openui-space); .openui-stack--row children flex 1 1 220px

### Card

A titled surface that groups related content. Use for one subject per card.

- `title`: `string`
- `children`: `Component[]` (optional)
- `subtitle`: `string` (optional)

Styled from `app/views/openui/components/_card.html.erb` + `app/assets/stylesheets/openui.css`:

- background: .openui-card var(--openui-surface)
- border: .openui-card 1px var(--openui-border)
- radius: .openui-card var(--openui-radius)
- typography: .openui-card__title 1.05em/600, .openui-card__subtitle 0.9em var(--openui-fg-muted)
- accent: none

### Text

A run of plain text. heading for a section title, caption for small secondary text.

- `text`: `string`
- `variant`: `"body" \| "heading" \| "caption"` (optional, default "body")

Styled from `app/views/openui/components/_text.html.erb` + `app/assets/stylesheets/openui.css`:

- background: none
- border: none
- radius: none
- typography: .openui-text--heading 1.25em/650, .openui-text--caption 0.875em var(--openui-fg-muted)
- accent: none

### Table

A table built from columns. Each Col carries its header and its cell values in row order.

- `columns`: `Col[]`
- `caption`: `string` (optional)

Styled from `app/views/openui/components/_table.html.erb` + `app/assets/stylesheets/openui.css`:

- background: none
- border: .openui-table__th, .openui-table__td bottom var(--openui-border)
- radius: none
- typography: .openui-table__th 0.85em uppercase var(--openui-fg-muted); .openui-table tabular-nums
- accent: .openui-table__sort arrow (currentColor)

### Col

One table column: a header label and the cell values, one per row. Right-align numbers. sort marks the column the rows are ordered by.

- `label`: `string`
- `data`: `any[]`
- `align`: `"left" \| "right"` (optional, default "left")
- `sort`: `"asc" \| "desc"` (optional)

Styled from `app/views/openui/components/_col.html.erb` + `app/assets/stylesheets/openui.css`:

- background: none
- border: drawn by Table
- radius: none
- typography: .openui-col__label 600 (outside a Table)
- accent: none
- note: Read by the Table partial; standalone it renders as a definition list.

### KeyValue

Label and value pairs for facts about one thing (specs, totals, settings).

- `items`: `{label: string, value: any}[]`
- `title`: `string` (optional)

Styled from `app/views/openui/components/_key_value.html.erb` + `app/assets/stylesheets/openui.css`:

- background: none
- border: none
- radius: none
- typography: .openui-kv__label var(--openui-fg-muted), .openui-kv__value 500
- accent: none

### Callout

A highlighted note. info for context, tip for advice, warning for caveats, danger for risks or losses.

- `text`: `string`
- `variant`: `"info" \| "tip" \| "warning" \| "danger"` (optional, default "info")
- `title`: `string` (optional)

Styled from `app/views/openui/components/_callout.html.erb` + `app/assets/stylesheets/openui.css`:

- background: .openui-callout var(--openui-surface)
- border: .openui-callout 3px left, per variant
- radius: .openui-callout 6px
- typography: .openui-callout__title 600
- accent: --openui-info, --openui-tip, --openui-warning, --openui-danger

### Chart

A bar, line or pie chart. labels are the x axis (or the pie slices); each series has a name and one number per label. Use bar to compare, line for trends over time, pie for shares of a whole (first series only).

- `labels`: `string[]`
- `series`: `{name: string, data: number[]}[]`
- `variant`: `"bar" \| "line" \| "pie"` (optional, default "bar")
- `title`: `string` (optional)

Styled from `app/views/openui/components/_chart.html.erb` + `app/assets/stylesheets/openui.css`:

- background: none
- border: .openui-chart__axis stroke var(--openui-border)
- radius: none
- typography: .openui-chart__tick, .openui-chart__label 11px var(--openui-fg-muted)
- accent: --openui-s1 to --openui-s8 (.openui-chart__series-0 to -7)
- note: Inline SVG from openui_chart_svg and openui_pie_svg, no JavaScript. To use a chart library, override _chart.html.erb: it receives labels (string[]), series ([{name, data: number[]}]) and variant (bar, line, pie; pie reads the first series).

### Section

A titled region of the answer that groups several components under one heading.

- `title`: `string`
- `children`: `Component[]`
- `description`: `string` (optional)

Styled from `app/views/openui/components/_section.html.erb`:

- background: none
- border: border-b border-gray-200 dark:border-gray-800
- radius: none
- typography: text-lg font-semibold text-gray-900; text-sm text-gray-500
- accent: none

### Divider

A horizontal rule between groups of content, with an optional short label.

- `label`: `string` (optional)

Styled from `app/views/openui/components/_divider.html.erb`:

- background: bg-gray-200 dark:bg-gray-800 (labelled rule)
- border: border-t border-gray-200 dark:border-gray-800
- radius: none
- typography: text-xs font-medium uppercase tracking-wide text-gray-500
- accent: none

### Markdown

Formatted prose: paragraphs, # headings, - and 1. lists, **bold**, *italic* and `code`. No links, images or HTML.

- `text`: `string`

Styled from `app/views/openui/components/_markdown.html.erb`:

- background: code: bg-gray-100 dark:bg-gray-800
- border: none
- radius: code: rounded
- typography: text-sm text-gray-700 dark:text-gray-300; headings font-semibold text-gray-900; font-mono
- accent: none
- note: Tags and their classes come from openui_markdown in lib/openui/rails/helper.rb.

### Metric

One headline number (KPI) with a label. unit $ € or £ goes before the number, % right after it, any other unit after a space. delta is the percent change versus the prior period.

- `label`: `string`
- `value`: `number`
- `unit`: `string` (optional)
- `delta`: `number` (optional)
- `caption`: `string` (optional)

Styled from `app/views/openui/components/_metric.html.erb`:

- background: bg-white dark:bg-gray-900
- border: border border-gray-200 dark:border-gray-800
- radius: rounded-lg
- typography: text-3xl font-semibold tracking-tight; text-sm font-medium text-gray-500
- accent: text-green-600 dark:text-green-400, text-red-600 dark:text-red-400

### Badge

A short status label. success for done or healthy, warning for at risk, danger for failed or blocked, info for in progress.

- `text`: `string`
- `tone`: `"neutral" \| "info" \| "success" \| "warning" \| "danger"` (optional, default "neutral")

Styled from `app/views/openui/components/_badge.html.erb`:

- background: bg-gray-100 bg-blue-50 bg-green-50 bg-yellow-50 bg-red-50 (per tone)
- border: ring-1 ring-inset ring-gray-500/20 ring-green-600/20 (per tone)
- radius: rounded-full
- typography: text-xs font-medium
- accent: text-gray-700 text-blue-700 text-green-700 text-yellow-800 text-red-700 (per tone)

### List

A bulleted or numbered list of short text items.

- `items`: `string[]`
- `variant`: `"bullet" \| "ordered"` (optional, default "bullet")

Styled from `app/views/openui/components/_list.html.erb`:

- background: none
- border: none
- radius: none
- typography: text-sm text-gray-700 dark:text-gray-300
- accent: marker:text-gray-400 dark:marker:text-gray-500

### Checklist

Tasks with done or not-done state, for plans, onboarding steps and requirements.

- `items`: `{label: string, done?: boolean}[]`
- `title`: `string` (optional)

Styled from `app/views/openui/components/_checklist.html.erb`:

- background: none
- border: none
- radius: none
- typography: text-sm; done: line-through text-gray-500
- accent: text-green-600 dark:text-green-400; open: text-gray-300

### Timeline

Events in time order, each with a title, an optional time and an optional detail line.

- `items`: `{title: string, time?: string, text?: string}[]`

Styled from `app/views/openui/components/_timeline.html.erb`:

- background: none
- border: border-s border-gray-200 dark:border-gray-800
- radius: rounded-full (dot)
- typography: text-xs text-gray-500; text-sm font-semibold
- accent: bg-blue-600 dark:bg-blue-500

### Form

Groups input controls and a submit Button. name identifies the form to the host.

- `name`: `string`
- `children`: `Component[]`
- `title`: `string` (optional)

Styled from `app/views/openui/components/_form.html.erb`:

- background: bg-white dark:bg-gray-900
- border: border border-gray-200 dark:border-gray-800
- radius: rounded-lg
- typography: text-base font-semibold
- accent: none

### Input

A labelled text field. type textarea for long text.

- `name`: `string`
- `label`: `string` (optional)
- `placeholder`: `string` (optional)
- `type`: `"text" \| "email" \| "number" \| "date" \| "textarea"` (optional, default "text")
- `value`: `string` (optional)

Styled from `app/views/openui/components/_input.html.erb`:

- background: bg-white dark:bg-gray-950
- border: border border-gray-300 dark:border-gray-700
- radius: rounded-md
- typography: text-sm; label text-sm font-medium
- accent: focus:border-blue-500 focus:ring-blue-500

### Select

A labelled dropdown with one choice from options.

- `name`: `string`
- `options`: `string[]`
- `label`: `string` (optional)
- `value`: `string` (optional)

Styled from `app/views/openui/components/_select.html.erb`:

- background: bg-white dark:bg-gray-950
- border: border border-gray-300 dark:border-gray-700
- radius: rounded-md
- typography: text-sm; label text-sm font-medium
- accent: focus:border-blue-500 focus:ring-blue-500

### Checkbox

A single yes or no choice with a label.

- `name`: `string`
- `label`: `string`
- `checked`: `boolean` (optional)

Styled from `app/views/openui/components/_checkbox.html.erb`:

- background: none
- border: border-gray-300 dark:border-gray-700
- radius: rounded
- typography: text-sm
- accent: accent-blue-600 dark:accent-blue-500

### Button

A button that runs an action: @ToAssistant to continue the conversation, @OpenUrl to open a page. primary for the main action, secondary or ghost for the rest.

- `label`: `string`
- `action`: `ActionExpression` (optional)
- `variant`: `"primary" \| "secondary" \| "ghost"` (optional, default "primary")

Styled from `app/views/openui/components/_button.html.erb`:

- background: bg-blue-600 dark:bg-blue-500; secondary bg-white dark:bg-gray-800
- border: secondary ring-1 ring-inset ring-gray-300 dark:ring-gray-700
- radius: rounded-md
- typography: text-sm font-semibold
- accent: bg-blue-600 hover:bg-blue-500; ghost text-blue-600

### Image

An image with alt text and an optional caption. Without an https src it renders as a labelled image slot.

- `alt`: `string`
- `src`: `string` (optional)
- `caption`: `string` (optional)

Styled from `app/views/openui/components/_image.html.erb`:

- background: slot: bg-gray-50 dark:bg-gray-900
- border: slot: border-2 border-dashed border-gray-300 dark:border-gray-700
- radius: rounded-lg
- typography: caption text-sm text-gray-500
- accent: none

### Avatar

A person or team: initials (or an https photo), a name and an optional role line.

- `name`: `string`
- `subtitle`: `string` (optional)
- `src`: `string` (optional)

Styled from `app/views/openui/components/_avatar.html.erb`:

- background: bg-blue-100 dark:bg-blue-500/20
- border: none
- radius: rounded-full
- typography: text-sm font-medium text-gray-900; text-sm text-gray-500
- accent: text-blue-700 dark:text-blue-300

## Examples

### Layout

- **Stack, column** (Stack, Text): The default container: the answer reads top to bottom.
- **Stack, row** (Stack, Card, Text): Side-by-side items that wrap on narrow screens: stages, options, KPI strips.
- **Card** (Card, Text, Badge): One subject per surface: a customer, a project, a ticket.
- **Col (table column)** (Col): Only inside a Table. Col is a table column, not a layout column; use Stack row for columns of content.
- **Section** (Section, Text, KeyValue): A long answer with several parts, each under its own heading.
- **Divider** (Divider, Stack, Text): Separating groups inside one card or list, optionally with a label such as a date.

### Text

- **Heading, paragraph, caption** (Text): A direct answer: a heading, one or two sentences, and where the numbers came from.
- **Markdown** (Markdown): Prose with some structure: release notes, a summary with emphasis, short instructions.
- **Callout variants** (Callout, Stack): A note that must not be missed: context (info), advice (tip), a caveat (warning), a risk (danger).

### Data

- **Table with a sort hint** (Table, Col, Badge): Rows of records with the same fields, sorted by the column that matters.
- **KeyValue** (KeyValue): Facts about one thing: a subscription, an order, a server.
- **Metric (KPI)** (Metric, Stack): Headline numbers with their change since the last period.
- **Badge / status** (Badge, KeyValue): Status at a glance: build results, ticket state, account health.

### Charts

- **Bar chart** (Chart): Comparing amounts across categories or periods, one bar per series.
- **Line chart** (Chart): A trend over time.
- **Pie chart** (Chart): Shares of a whole with a handful of slices.

### Forms and inputs

- **Form with submit action** (Form, Input, Select, Checkbox, Button): Collecting details from the user; the submit Button's action carries the request.
- **Input types** (Input, Stack): A single value: text, email, number, date, or a longer note.
- **Select and Checkbox** (Select, Checkbox, Stack): One choice from a short list, and yes or no preferences.
- **Button variants** (Button, Stack): The main action, the alternatives, and a quiet way out.

### Lists

- **Bulleted and numbered lists** (List, Stack): Short items: highlights (bullets) or steps in order (numbers).
- **Checklist** (Checklist): Progress through a plan: onboarding, a launch, requirements met.
- **Timeline** (Timeline): What happened when: order tracking, incident history, a deal's activity.

### Media

- **Image slot** (Image): A screenshot, product photo or diagram. Without an https src it shows a labelled slot.
- **Avatar** (Avatar, Stack): People: an owner, an assignee, a team roster.

### Actions

- **Continue the conversation** (Button, Text, Stack): Suggested follow-ups; a click sends the message (and optional hidden context) as the next user turn.
- **Open a URL** (Button, Stack): Links to the record or document the answer is about.
- **Several steps in one action** (Button): One click that opens a page and tells the agent what happened.

### Composite examples

- **Dashboard card** (Card, Stack, Metric, Chart, Callout): A status report: KPIs, the trend behind them, and the one thing to watch.
- **Comparison table** (Stack, Text, Table, Col, Badge, Callout): Choosing between options: the facts side by side, then a recommendation.
- **Plan / pricing cards** (Stack, Card, Badge, Metric, List, Button): Presenting plans with what each includes and a way to pick one.
- **Email preview** (Card, KeyValue, Divider, Markdown, Stack, Button): A drafted email for the user to review before it is sent.
- **Org chart tile** (Card, Avatar, Divider, Stack, KeyValue, Badge): Who is on a team, who leads it, and what is open.

