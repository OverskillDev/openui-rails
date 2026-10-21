# frozen_string_literal: true

module OpenUI
  module Rails
    # What an agent can build with the catalog library: one entry per
    # example, each an OpenUI Lang program that the catalog page parses and
    # renders with the gem's own parser and renderer. CATALOG.md is generated
    # from the same data (`rake catalog:md`).
    module Catalog
      Entry = Struct.new(:id, :category, :title, :components, :use, :snippet, keyword_init: true)

      CATEGORIES = ["Layout", "Text", "Data", "Charts", "Forms and inputs", "Lists", "Media", "Actions", "Composite examples"].freeze

      STARTER_CSS = "app/assets/stylesheets/openui.css"

      # What a host restyles per component. Starter components are styled by
      # openui.css (classes and --openui-* variables); catalog components by
      # Tailwind utilities in their partial. Keys: background, border, radius,
      # type, accent; "none" where the component draws nothing of that kind.
      STYLES = {
        "Stack" => {background: "none", border: "none", radius: "none",
                    type: "inherits .openui-root (15px system-ui)", accent: "none",
                    notes: ".openui-stack gap: var(--openui-space); .openui-stack--row children flex 1 1 220px"},
        "Card" => {background: ".openui-card var(--openui-surface)", border: ".openui-card 1px var(--openui-border)",
                   radius: ".openui-card var(--openui-radius)", type: ".openui-card__title 1.05em/600, .openui-card__subtitle 0.9em var(--openui-fg-muted)",
                   accent: "none"},
        "Text" => {background: "none", border: "none", radius: "none",
                   type: ".openui-text--heading 1.25em/650, .openui-text--caption 0.875em var(--openui-fg-muted)", accent: "none"},
        "Table" => {background: "none", border: ".openui-table__th, .openui-table__td bottom var(--openui-border)", radius: "none",
                    type: ".openui-table__th 0.85em uppercase var(--openui-fg-muted); .openui-table tabular-nums",
                    accent: ".openui-table__sort arrow (currentColor)"},
        "Col" => {background: "none", border: "drawn by Table", radius: "none",
                  type: ".openui-col__label 600 (outside a Table)", accent: "none",
                  notes: "Read by the Table partial; standalone it renders as a definition list."},
        "KeyValue" => {background: "none", border: "none", radius: "none",
                       type: ".openui-kv__label var(--openui-fg-muted), .openui-kv__value 500", accent: "none"},
        "Callout" => {background: ".openui-callout var(--openui-surface)", border: ".openui-callout 3px left, per variant",
                      radius: ".openui-callout 6px", type: ".openui-callout__title 600",
                      accent: "--openui-info, --openui-tip, --openui-warning, --openui-danger"},
        "Chart" => {background: "none", border: ".openui-chart__axis stroke var(--openui-border)", radius: "none",
                    type: ".openui-chart__tick, .openui-chart__label 11px var(--openui-fg-muted)",
                    accent: "--openui-s1 to --openui-s8 (.openui-chart__series-0 to -7)",
                    notes: "Inline SVG from openui_chart_svg and openui_pie_svg, no JavaScript. To use a chart library, " \
                           "override _chart.html.erb: it receives labels (string[]), series ([{name, data: number[]}]) and " \
                           "variant (bar, line, pie; pie reads the first series)."},
        "Section" => {background: "none", border: "border-b border-gray-200 dark:border-gray-800", radius: "none",
                      type: "text-lg font-semibold text-gray-900; text-sm text-gray-500", accent: "none"},
        "Divider" => {background: "bg-gray-200 dark:bg-gray-800 (labelled rule)", border: "border-t border-gray-200 dark:border-gray-800",
                      radius: "none", type: "text-xs font-medium uppercase tracking-wide text-gray-500", accent: "none"},
        "Markdown" => {background: "code: bg-gray-100 dark:bg-gray-800", border: "none", radius: "code: rounded",
                       type: "text-sm text-gray-700 dark:text-gray-300; headings font-semibold text-gray-900; font-mono",
                       accent: "none", notes: "Tags and their classes come from openui_markdown in lib/openui/rails/helper.rb."},
        "Metric" => {background: "bg-white dark:bg-gray-900", border: "border border-gray-200 dark:border-gray-800", radius: "rounded-lg",
                     type: "text-3xl font-semibold tracking-tight; text-sm font-medium text-gray-500",
                     accent: "text-green-600 dark:text-green-400, text-red-600 dark:text-red-400"},
        "Badge" => {background: "bg-gray-100 bg-blue-50 bg-green-50 bg-yellow-50 bg-red-50 (per tone)",
                    border: "ring-1 ring-inset ring-gray-500/20 ring-green-600/20 (per tone)", radius: "rounded-full",
                    type: "text-xs font-medium", accent: "text-gray-700 text-blue-700 text-green-700 text-yellow-800 text-red-700 (per tone)"},
        "List" => {background: "none", border: "none", radius: "none",
                   type: "text-sm text-gray-700 dark:text-gray-300", accent: "marker:text-gray-400 dark:marker:text-gray-500"},
        "Checklist" => {background: "none", border: "none", radius: "none",
                        type: "text-sm; done: line-through text-gray-500", accent: "text-green-600 dark:text-green-400; open: text-gray-300"},
        "Timeline" => {background: "none", border: "border-s border-gray-200 dark:border-gray-800", radius: "rounded-full (dot)",
                       type: "text-xs text-gray-500; text-sm font-semibold", accent: "bg-blue-600 dark:bg-blue-500"},
        "Form" => {background: "bg-white dark:bg-gray-900", border: "border border-gray-200 dark:border-gray-800", radius: "rounded-lg",
                   type: "text-base font-semibold", accent: "none"},
        "Input" => {background: "bg-white dark:bg-gray-950", border: "border border-gray-300 dark:border-gray-700", radius: "rounded-md",
                    type: "text-sm; label text-sm font-medium", accent: "focus:border-blue-500 focus:ring-blue-500"},
        "Select" => {background: "bg-white dark:bg-gray-950", border: "border border-gray-300 dark:border-gray-700", radius: "rounded-md",
                     type: "text-sm; label text-sm font-medium", accent: "focus:border-blue-500 focus:ring-blue-500"},
        "Checkbox" => {background: "none", border: "border-gray-300 dark:border-gray-700", radius: "rounded",
                       type: "text-sm", accent: "accent-blue-600 dark:accent-blue-500"},
        "Button" => {background: "bg-blue-600 dark:bg-blue-500; secondary bg-white dark:bg-gray-800",
                     border: "secondary ring-1 ring-inset ring-gray-300 dark:ring-gray-700", radius: "rounded-md",
                     type: "text-sm font-semibold", accent: "bg-blue-600 hover:bg-blue-500; ghost text-blue-600"},
        "Image" => {background: "slot: bg-gray-50 dark:bg-gray-900", border: "slot: border-2 border-dashed border-gray-300 dark:border-gray-700",
                    radius: "rounded-lg", type: "caption text-sm text-gray-500", accent: "none"},
        "Avatar" => {background: "bg-blue-100 dark:bg-blue-500/20", border: "none", radius: "rounded-full",
                     type: "text-sm font-medium text-gray-900; text-sm text-gray-500", accent: "text-blue-700 dark:text-blue-300"}
      }.freeze

      ENTRIES = [
        # ── Layout ─────────────────────────────────────────────────────────
        Entry.new(id: "stack-column", category: "Layout", title: "Stack, column", components: %w[Stack Text],
          use: "The default container: the answer reads top to bottom.",
          snippet: <<~OUI),
            root = Stack([title, body, note])
            title = Text("Quarterly review", "heading")
            body = Text("Three teams shipped ahead of plan; one slipped by a week.")
            note = Text("Updated 2 hours ago", "caption")
          OUI
        Entry.new(id: "stack-row", category: "Layout", title: "Stack, row", components: %w[Stack Card Text],
          use: "Side-by-side items that wrap on narrow screens: stages, options, KPI strips.",
          snippet: <<~OUI),
            root = Stack([design, build, launch], "row")
            design = Card("Design", [Text("4 open tasks")])
            build = Card("Build", [Text("9 open tasks")])
            launch = Card("Launch", [Text("2 open tasks")])
          OUI
        Entry.new(id: "card", category: "Layout", title: "Card", components: %w[Card Text Badge],
          use: "One subject per surface: a customer, a project, a ticket.",
          snippet: <<~OUI),
            root = Card("Acme Corp", [summary, status], "Customer since 2021")
            summary = Text("Enterprise plan, 240 seats, renews in March.")
            status = Badge("Healthy", "success")
          OUI
        Entry.new(id: "col", category: "Layout", title: "Col (table column)", components: %w[Col],
          use: "Only inside a Table. Col is a table column, not a layout column; use Stack row for columns of content.",
          snippet: <<~OUI),
            root = Col("Regions", ["North", "South", "West"])
          OUI
        Entry.new(id: "section", category: "Layout", title: "Section", components: %w[Section Text KeyValue],
          use: "A long answer with several parts, each under its own heading.",
          snippet: <<~OUI),
            root = Section("Pipeline", [body, counts], "Open opportunities this quarter")
            body = Text("Twelve deals are open; four are in negotiation.")
            counts = KeyValue([{label: "Open", value: 12}, {label: "Negotiation", value: 4}, {label: "Closing this month", value: 3}])
          OUI
        Entry.new(id: "divider", category: "Layout", title: "Divider", components: %w[Divider Stack Text],
          use: "Separating groups inside one card or list, optionally with a label such as a date.",
          snippet: <<~OUI),
            root = Stack([today, plain, earlier, labelled, older])
            today = Text("Standup: release branch cut, QA starts tomorrow.")
            plain = Divider()
            earlier = Text("Review: pricing page copy approved.")
            labelled = Divider("Yesterday")
            older = Text("Retro: fewer meetings on Fridays.")
          OUI

        # ── Text ───────────────────────────────────────────────────────────
        Entry.new(id: "text", category: "Text", title: "Heading, paragraph, caption", components: %w[Text],
          use: "A direct answer: a heading, one or two sentences, and where the numbers came from.",
          snippet: <<~OUI),
            root = Stack([heading, body, source])
            heading = Text("Weekly summary", "heading")
            body = Text("Revenue grew 8% week over week, driven by the Team plan.")
            source = Text("Source: billing export, Oct 19", "caption")
          OUI
        Entry.new(id: "markdown", category: "Text", title: "Markdown", components: %w[Markdown],
          use: "Prose with some structure: release notes, a summary with emphasis, short instructions.",
          snippet: <<~'OUI'),
            root = Markdown("## Release notes\nThis week we shipped **faster exports** and fixed the *timezone* bug in `reports.csv`.\n\n- CSV export is 3x faster\n- Scheduled reports use the account timezone\n\n1. Update the app\n2. Re-run any failed exports")
          OUI
        Entry.new(id: "callouts", category: "Text", title: "Callout variants", components: %w[Callout Stack],
          use: "A note that must not be missed: context (info), advice (tip), a caveat (warning), a risk (danger).",
          snippet: <<~OUI),
            root = Stack([info, tip, warning, danger])
            info = Callout("Numbers are from the last full week.", "info")
            tip = Callout("Annual billing saves two months.", "tip", "Tip")
            warning = Callout("Three invoices are past due.", "warning", "Heads up")
            danger = Callout("Payment failed for 2 accounts; access ends Friday.", "danger", "Action needed")
          OUI

        # ── Data ───────────────────────────────────────────────────────────
        Entry.new(id: "table", category: "Data", title: "Table with a sort hint", components: %w[Table Col Badge],
          use: "Rows of records with the same fields, sorted by the column that matters.",
          snippet: <<~OUI),
            root = Table([account, plan, mrr, status], "Top accounts by MRR")
            account = Col("Account", ["Acme", "Globex", "Initech"])
            plan = Col("Plan", ["Enterprise", "Team", "Team"])
            mrr = Col("MRR (USD)", [4200, 1800, 950], "right", "desc")
            status = Col("Status", [Badge("Healthy", "success"), Badge("At risk", "warning"), Badge("Churning", "danger")])
          OUI
        Entry.new(id: "key-value", category: "Data", title: "KeyValue", components: %w[KeyValue],
          use: "Facts about one thing: a subscription, an order, a server.",
          snippet: <<~OUI),
            root = KeyValue([{label: "Plan", value: "Team"}, {label: "Seats", value: 12}, {label: "Renews", value: "Mar 1, 2027"}, {label: "Owner", value: "Dana Lee"}], "Subscription")
          OUI
        Entry.new(id: "metric", category: "Data", title: "Metric (KPI)", components: %w[Metric Stack],
          use: "Headline numbers with their change since the last period.",
          snippet: <<~OUI),
            root = Stack([mrr, churn, nps], "row")
            mrr = Metric("MRR", 48200, "$", 12.5, "vs last month")
            churn = Metric("Churn", 2.1, "%", -0.4)
            nps = Metric("NPS", 61, null, 0, "no change")
          OUI
        Entry.new(id: "badge", category: "Data", title: "Badge / status", components: %w[Badge KeyValue],
          use: "Status at a glance: build results, ticket state, account health.",
          snippet: <<~OUI),
            root = KeyValue([build, deploy, review, scan, docs], "Release 4.2")
            build = {label: "Build", value: Badge("Passing", "success")}
            deploy = {label: "Deploy", value: Badge("In progress", "info")}
            review = {label: "Review", value: Badge("Changes requested", "warning")}
            scan = {label: "Security scan", value: Badge("2 critical", "danger")}
            docs = {label: "Docs", value: Badge("Draft")}
          OUI

        # ── Charts ─────────────────────────────────────────────────────────
        Entry.new(id: "chart-bar", category: "Charts", title: "Bar chart", components: %w[Chart],
          use: "Comparing amounts across categories or periods, one bar per series.",
          snippet: <<~OUI),
            root = Chart(["Q1", "Q2", "Q3", "Q4"], [{name: "2025", data: [120, 150, 170, 210]}, {name: "2026", data: [140, 180, 205, 260]}], "bar", "Revenue by quarter (USD k)")
          OUI
        Entry.new(id: "chart-line", category: "Charts", title: "Line chart", components: %w[Chart],
          use: "A trend over time.",
          snippet: <<~OUI),
            root = Chart(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], [{name: "Signups", data: [32, 41, 38, 52, 61, 30, 27]}], "line", "Signups this week")
          OUI
        Entry.new(id: "chart-pie", category: "Charts", title: "Pie chart", components: %w[Chart],
          use: "Shares of a whole with a handful of slices.",
          snippet: <<~OUI),
            root = Chart(["Organic", "Paid", "Referral", "Email"], [{name: "Visits", data: [48, 27, 15, 10]}], "pie", "Traffic by source (%)")
          OUI

        # ── Forms and inputs ───────────────────────────────────────────────
        Entry.new(id: "form", category: "Forms and inputs", title: "Form with submit action", components: %w[Form Input Select Checkbox Button],
          use: "Collecting details from the user; the submit Button's action carries the request.",
          snippet: <<~OUI),
            root = Form("trial", [name, email, plan, notes, terms, submit], "Start a free trial")
            name = Input("name", "Full name", "Dana Lee")
            email = Input("email", "Work email", "dana@company.com", "email")
            plan = Select("plan", ["Starter", "Team", "Business"], "Plan", "Team")
            notes = Input("notes", "Anything we should know?", "Optional", "textarea")
            terms = Checkbox("terms", "I agree to the terms", true)
            submit = Button("Start trial", @ToAssistant("Start my trial"))
          OUI
        Entry.new(id: "input", category: "Forms and inputs", title: "Input types", components: %w[Input Stack],
          use: "A single value: text, email, number, date, or a longer note.",
          snippet: <<~OUI),
            root = Stack([company, start, seats])
            company = Input("company", "Company", "Acme Inc.")
            start = Input("start", "Start date", null, "date")
            seats = Input("seats", "Seats", "10", "number")
          OUI
        Entry.new(id: "select-checkbox", category: "Forms and inputs", title: "Select and Checkbox", components: %w[Select Checkbox Stack],
          use: "One choice from a short list, and yes or no preferences.",
          snippet: <<~OUI),
            root = Stack([region, digest, sms])
            region = Select("region", ["US East", "US West", "EU", "APAC"], "Data region", "EU")
            digest = Checkbox("digest", "Send me the weekly digest", true)
            sms = Checkbox("sms", "Text me when a deploy fails")
          OUI
        Entry.new(id: "button", category: "Forms and inputs", title: "Button variants", components: %w[Button Stack],
          use: "The main action, the alternatives, and a quiet way out.",
          snippet: <<~OUI),
            root = Stack([approve, changes, cancel])
            approve = Button("Approve", @ToAssistant("Approve the plan"))
            changes = Button("Request changes", @ToAssistant("Request changes to the plan"), "secondary")
            cancel = Button("Cancel", null, "ghost")
          OUI

        # ── Lists ──────────────────────────────────────────────────────────
        Entry.new(id: "list", category: "Lists", title: "Bulleted and numbered lists", components: %w[List Stack],
          use: "Short items: highlights (bullets) or steps in order (numbers).",
          snippet: <<~OUI),
            root = Stack([highlights, steps])
            highlights = List(["Exports are 3x faster", "New timezone setting", "Dark mode for reports"])
            steps = List(["Open Settings", "Choose Billing", "Click Update card"], "ordered")
          OUI
        Entry.new(id: "checklist", category: "Lists", title: "Checklist", components: %w[Checklist],
          use: "Progress through a plan: onboarding, a launch, requirements met.",
          snippet: <<~OUI),
            root = Checklist([{label: "Connect your domain", done: true}, {label: "Invite your team", done: true}, {label: "Import contacts"}, {label: "Send your first campaign"}], "Onboarding")
          OUI
        Entry.new(id: "timeline", category: "Lists", title: "Timeline", components: %w[Timeline],
          use: "What happened when: order tracking, incident history, a deal's activity.",
          snippet: <<~OUI),
            root = Timeline([{title: "Order placed", time: "Oct 14, 9:12", text: "Order 4821, 3 items"}, {title: "Shipped", time: "Oct 15, 16:40", text: "UPS 1Z999AA10123456784"}, {title: "Out for delivery", time: "Oct 17, 08:05"}])
          OUI

        # ── Media ──────────────────────────────────────────────────────────
        Entry.new(id: "image", category: "Media", title: "Image slot", components: %w[Image],
          use: "A screenshot, product photo or diagram. Without an https src it shows a labelled slot.",
          snippet: <<~OUI),
            root = Image("Screenshot of the new reports dashboard", null, "Figure 1. The reports dashboard after the redesign")
          OUI
        Entry.new(id: "avatar", category: "Media", title: "Avatar", components: %w[Avatar Stack],
          use: "People: an owner, an assignee, a team roster.",
          snippet: <<~OUI),
            root = Stack([dana, sam, priya])
            dana = Avatar("Dana Lee", "Head of Sales")
            sam = Avatar("Sam Ortiz", "Support lead")
            priya = Avatar("Priya Nair", "Engineer")
          OUI

        # ── Actions ────────────────────────────────────────────────────────
        Entry.new(id: "action-continue", category: "Actions", title: "Continue the conversation", components: %w[Button Text Stack],
          use: "Suggested follow-ups; a click sends the message (and optional hidden context) as the next user turn.",
          snippet: <<~OUI),
            root = Stack([ask, risk, explain])
            ask = Text("Want me to dig deeper?")
            risk = Button("Show the accounts at risk", @ToAssistant("Show the accounts at risk", {segment: "at_risk"}))
            explain = Button("Explain the churn number", @ToAssistant("Explain the churn number"), "secondary")
          OUI
        Entry.new(id: "action-open-url", category: "Actions", title: "Open a URL", components: %w[Button Stack],
          use: "Links to the record or document the answer is about.",
          snippet: <<~OUI),
            root = Stack([invoice, docs])
            invoice = Button("Open invoice 4821", @OpenUrl("https://billing.example.com/invoices/4821"))
            docs = Button("Read the API docs", @OpenUrl("https://docs.example.com/api"), "ghost")
          OUI
        Entry.new(id: "action-steps", category: "Actions", title: "Several steps in one action", components: %w[Button],
          use: "One click that opens a page and tells the agent what happened.",
          snippet: <<~OUI),
            root = Button("Open the quote and summarize it", Action([@OpenUrl("https://crm.example.com/quotes/77"), @ToAssistant("Summarize quote 77")]), "secondary")
          OUI

        # ── Composite examples ─────────────────────────────────────────────
        Entry.new(id: "dashboard-card", category: "Composite examples", title: "Dashboard card", components: %w[Card Stack Metric Chart Callout],
          use: "A status report: KPIs, the trend behind them, and the one thing to watch.",
          snippet: <<~OUI),
            root = Card("Sales this month", [kpis, trend, note], "Oct 1 to Oct 20")
            kpis = Stack([revenue, deals, winrate], "row")
            revenue = Metric("Revenue", 182400, "$", 9.2)
            deals = Metric("Deals won", 37, null, 4.1)
            winrate = Metric("Win rate", 28, "%", -1.5)
            trend = Chart(["W1", "W2", "W3"], [{name: "Revenue", data: [52, 61, 69]}], "line", "Weekly revenue (USD k)")
            note = Callout("Win rate dipped after the price change on Oct 8.", "warning")
          OUI
        Entry.new(id: "comparison-table", category: "Composite examples", title: "Comparison table", components: %w[Stack Text Table Col Badge Callout],
          use: "Choosing between options: the facts side by side, then a recommendation.",
          snippet: <<~OUI),
            root = Stack([title, table, pick])
            title = Text("CRM options for a 12-person team", "heading")
            table = Table([tool, price, seats, sso, fit])
            tool = Col("Tool", ["Pipedrive", "HubSpot", "Salesforce"])
            price = Col("Per seat / month (USD)", [24, 50, 80], "right", "asc")
            seats = Col("Min seats", [1, 5, 10], "right")
            sso = Col("SSO", ["No", "Yes", "Yes"])
            fit = Col("Fit", [Badge("No SSO", "danger"), Badge("Best fit", "success"), Badge("Overkill", "warning")])
            pick = Callout("HubSpot is the cheapest option with SSO.", "tip", "Recommendation")
          OUI
        Entry.new(id: "pricing-cards", category: "Composite examples", title: "Plan / pricing cards", components: %w[Stack Card Badge Metric List Button],
          use: "Presenting plans with what each includes and a way to pick one.",
          snippet: <<~OUI),
            root = Stack([starter, team], "row")
            starter = Card("Starter", [starterPrice, starterFeatures, starterPick], "For individuals")
            starterPrice = Metric("Per month", 19, "$")
            starterFeatures = List(["1 seat", "5 projects", "Email support"])
            starterPick = Button("Choose Starter", @ToAssistant("Sign me up for Starter"), "secondary")
            team = Card("Team", [popular, teamPrice, teamFeatures, teamPick], "For growing teams")
            popular = Badge("Most popular", "info")
            teamPrice = Metric("Per month", 49, "$")
            teamFeatures = List(["5 seats", "Unlimited projects", "SSO and audit log"])
            teamPick = Button("Choose Team", @ToAssistant("Sign me up for Team"))
          OUI
        Entry.new(id: "email-preview", category: "Composite examples", title: "Email preview", components: %w[Card KeyValue Divider Markdown Stack Button],
          use: "A drafted email for the user to review before it is sent.",
          snippet: <<~'OUI'),
            root = Card("Re: Renewal quote for Acme", [meta, rule, body, actions], "Draft reply")
            meta = KeyValue([{label: "From", value: "alex@company.com"}, {label: "To", value: "dana@acme.com"}, {label: "Status", value: "Not sent"}])
            rule = Divider()
            body = Markdown("Hi Dana,\n\nThanks for the call. The renewal quote for **240 seats** is attached, with the multi-year discount applied.\n\n- Term: 24 months\n- Start: March 1, 2027\n\nBest,\nAlex")
            actions = Stack([send, edit], "row")
            send = Button("Send", @ToAssistant("Send the email"))
            edit = Button("Edit draft", @ToAssistant("Let me edit the email"), "secondary")
          OUI
        Entry.new(id: "org-chart-tile", category: "Composite examples", title: "Org chart tile", components: %w[Card Avatar Divider Stack KeyValue Badge],
          use: "Who is on a team, who leads it, and what is open.",
          snippet: <<~OUI)
            root = Card("Sales team", [lead, rule, reports, stats], "Reports to the CRO")
            lead = Avatar("Dana Lee", "VP Sales")
            rule = Divider("Direct reports")
            reports = Stack([sam, priya, leo])
            sam = Avatar("Sam Ortiz", "Account executive, Enterprise")
            priya = Avatar("Priya Nair", "Account executive, Mid-market")
            leo = Avatar("Leo Park", "SDR lead")
            stats = KeyValue([{label: "Headcount", value: 9}, {label: "Open roles", value: Badge("2 hiring", "info")}])
          OUI
      ].freeze

      module_function

      def library
        @library ||= CatalogLibrary.build
      end

      def entries
        ENTRIES
      end

      def categories
        CATEGORIES.map { |name| [name, ENTRIES.select { |e| e.category == name }] }
      end

      def status(component_name)
        StarterLibrary.build.component?(component_name) ? "starter" : "added-in-catalog"
      end

      # app/views path of the partial a component renders with.
      def partial_path(component_name)
        renders = library.component(component_name).renders
        "app/views/#{File.dirname(renders)}/_#{File.basename(renders)}.html.erb"
      end

      def styled_from(component_name)
        STYLES.fetch(component_name)
      end

      # Parse and render one entry with the catalog library.
      # Returns [html, problems], where problems lists errors, unresolved
      # references and orphaned statements (all should be empty).
      def render(entry, view_context:, mount_id: "catalog-#{entry.id}")
        result = library.parse(entry.snippet)
        renderer = Renderer.new(library, view_context: view_context, mount_id: mount_id)
        html = renderer.render(result)
        problems = (result.errors + renderer.errors).map { |e| "#{e.code}: #{e.message}" }
        problems += result.unresolved.map { |name| "unresolved: #{name}" }
        problems += result.orphaned.map { |name| "orphaned: #{name}" }
        [html, problems]
      end

      # CATALOG.md, generated from the library and the entries.
      def markdown
        lib = library
        any = "(#{lib.component_names.join(" | ")})[]"
        sig = ->(text) { text.gsub(any, "Component[]").gsub("|", "\\|") }
        lines = []
        lines << "# Component catalog"
        lines << ""
        lines << "Every component an agent can use with `OpenUI::Rails::CatalogLibrary`, generated from"
        lines << "`lib/openui/rails/catalog.rb` by `bundle exec rake catalog:md`; do not edit by hand."
        lines << "The live page is `/catalog` in the dummy app (`cd test/dummy && bundle exec puma -p 3530 config.ru`),"
        lines << "or `/openui/catalog` in a host that mounts the engine and sets `OpenUI::Rails.catalog = true`."
        lines << ""
        lines << "- **starter**: in `OpenUI::Rails::StarterLibrary`, styled by `#{STARTER_CSS}` (classes and `--openui-*` variables)."
        lines << "- **added-in-catalog**: added by `OpenUI::Rails::CatalogLibrary`, styled with Tailwind utility classes in the partial."
        lines << "  A host that renders these needs Tailwind to scan the gem's views, for example in Tailwind 4:"
        lines << "  `@source \"<path from bundle show openui-rails>/app/views\";`."
        lines << ""
        lines << "Arguments are positional, in the order shown; `?` marks optional ones. `Component[]` stands for a"
        lines << "slot that takes any component in the library; the prompt spells it out as the full union."
        lines << "Chart's `pie` variant and Col's `sort` hint are recent additions to the starter components."
        lines << ""
        lines << "## Components"
        lines << ""
        lines << "| Component | Category | Status | OpenUI Lang signature | Partial |"
        lines << "| --- | --- | --- | --- | --- |"
        lib.components.each_value do |c|
          category = ENTRIES.find { |e| e.components.first == c.name }&.category ||
            ENTRIES.find { |e| e.components.include?(c.name) }&.category
          lines << "| #{c.name} | #{category} | #{status(c.name)} | `#{sig.call(c.signature(lib))}` | `#{partial_path(c.name)}` |"
        end
        lines << ""
        lines << "## Arguments and styling"
        lines << ""
        lib.components.each_value do |c|
          lines << "### #{c.name}"
          lines << ""
          lines << c.description
          lines << ""
          c.params.each do |param|
            extra = []
            extra << "optional" if param.optional_in_signature?
            extra << "default #{param.default.inspect}" unless param.default.nil?
            lines << "- `#{param.name}`: `#{sig.call(param.type.signature(lib))}`#{extra.empty? ? "" : " (#{extra.join(", ")})"}"
          end
          lines << ""
          style = styled_from(c.name)
          source = status(c.name) == "starter" ? "`#{partial_path(c.name)}` + `#{STARTER_CSS}`" : "`#{partial_path(c.name)}`"
          lines << "Styled from #{source}:"
          lines << ""
          %i[background border radius type accent].each { |key| lines << "- #{key == :type ? "typography" : key}: #{style[key]}" }
          lines << "- note: #{style[:notes]}" if style[:notes]
          lines << ""
        end
        lines << "## Examples"
        lines << ""
        CATEGORIES.each do |name|
          lines << "### #{name}"
          lines << ""
          ENTRIES.select { |e| e.category == name }.each do |e|
            lines << "- **#{e.title}** (#{e.components.join(", ")}): #{e.use}"
          end
          lines << ""
        end
        lines.join("\n")
      end
    end
  end
end
