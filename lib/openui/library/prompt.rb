# frozen_string_literal: true

require "json"

module OpenUI
  class Library
    # Generates the system prompt from a LibrarySpec (prompt.md section 4).
    # A port of generatePrompt in thesysdev/openui
    # packages/lang-core/src/parser/prompt.ts (MIT), kept byte-identical so
    # models behave the same against a Ruby host; test/library/prompt_test.rb
    # compares against prompts dumped from the reference generator.
    module Prompt
      PREAMBLE = "You are an AI assistant that responds using openui-lang, a declarative UI language. " \
                 "Your ENTIRE response must be valid openui-lang code — no markdown, no explanations, just openui-lang."
      ACTION_HEADER = "## Action — Button Behavior"
      RESTRICTED_SLOT = /[:|] @[A-Z]/

      OPTION_KEYS = {
        "toolCalls" => :tool_calls, "editMode" => :edit_mode, "inlineMode" => :inline_mode,
        "builtinFunctions" => :builtin_functions, "toolExamples" => :tool_examples,
        "additionalRules" => :additional_rules, "preamble" => :preamble, "examples" => :examples,
        "tools" => :tools, "bindings" => :bindings
      }.freeze

      module_function

      # Accept snake_case symbols or the camelCase keys of the reference PromptOptions.
      def normalize_options(options)
        out = {}
        (options || {}).each do |k, v|
          key = OPTION_KEYS[k.to_s] || k.to_s.gsub(/([a-z])([A-Z])/) { "#{$1}_#{$2.downcase}" }.to_sym
          out[key] = v
        end
        out
      end

      # @param spec [Hash] with "root", "components" => {name => {"signature", "description"}},
      #   "componentGroups", "functions", "actions"
      def generate(spec, options = {})
        opts = normalize_options(options)
        root_name = spec["root"] || "Root"
        components = spec["components"] || {}
        tools = opts[:tools] || []
        has_tools = !tools.empty?
        tool_calls = opts.key?(:tool_calls) ? !!opts[:tool_calls] : has_tools
        bindings = opts.key?(:bindings) ? !!opts[:bindings] : tool_calls
        supports_expressions = tool_calls || bindings
        uses_action_expression = components.values.any? do |c|
          sig = c["signature"].to_s
          sig.include?("ActionExpression") || RESTRICTED_SLOT.match?(sig)
        end
        flags = {tool_calls: tool_calls, bindings: bindings, supports_expressions: supports_expressions,
                 uses_action_expression: uses_action_expression}

        parts = []
        parts << (opts[:preamble] || PREAMBLE)
        parts << ""
        parts << syntax_rules(root_name, flags)
        parts << ""
        parts << component_signatures(spec, flags)

        custom_functions = (spec["functions"] || {}).values.map { |f| function_line(f["signature"], f["description"]) }
        builtin_functions = opts.key?(:builtin_functions) ? !!opts[:builtin_functions] : supports_expressions
        if builtin_functions
          parts << ""
          parts << builtin_functions_section(custom_functions, tool_calls)
        elsif !custom_functions.empty?
          parts << ""
          parts << "## Built-in Functions\n\n#{custom_functions.join("\n")}"
        end

        if tool_calls
          parts << ""
          parts << query_section
          parts << ""
          parts << mutation_section
        end

        custom_actions = (spec["actions"] || {}).values.map { |a| "- #{function_line(a["signature"], a["description"])}" }
        if uses_action_expression
          parts << ""
          parts << action_section(flags, custom_actions)
        elsif !custom_actions.empty?
          parts << ""
          parts << "#{ACTION_HEADER}\n\nPass one step, or Action([...]) with several steps, as a button's action.\n\nAvailable steps:\n#{custom_actions.join("\n")}"
        end

        if tool_calls && bindings
          parts << ""
          parts << interactive_filters_section
        end

        if tool_calls
          parts << ""
          parts << tool_workflow_section
        end

        unless tools.empty?
          parts << ""
          parts << tools_section(tools)
        end

        parts << ""
        parts << streaming_rules(root_name, flags)

        examples = Array(opts[:examples]) + Array(opts[:tool_examples])
        unless examples.empty?
          parts << ""
          parts << "## Examples"
          parts << ""
          examples.each do |ex|
            parts << ex
            parts << ""
          end
        end

        if opts[:edit_mode]
          parts << ""
          parts << edit_mode_section
        end

        if opts[:inline_mode]
          parts << ""
          parts << inline_mode_section
        end

        parts << important_rules(root_name, flags)

        rules = Array(opts[:additional_rules])
        unless rules.empty?
          parts << ""
          rules.each { |r| parts << "- #{r}" }
        end

        parts.join("\n")
      end

      def function_line(signature, description)
        description ? "@#{signature} — #{description}" : "@#{signature}"
      end

      def syntax_rules(root_name, flags)
        lines = [
          "## Syntax Rules",
          "",
          "1. Each statement is on its own line: `identifier = Expression`",
          "2. `root` is the entry point — every program must define `root = #{root_name}(...)`",
          '3. Expressions are: strings ("..."), numbers, booleans (true/false), null, arrays ([...]), objects ({...}), or component calls TypeName(arg1, arg2, ...)',
          "4. Use references for readability: define `name = ...` on one line, then use `name` later",
          "5. EVERY variable (except root) MUST be referenced by at least one other variable. Unreferenced variables are silently dropped and will NOT render. Always include defined variables in their parent's children/items array.",
          '6. Arguments are POSITIONAL (order matters, not names). Write `SomeComp([children], "row", "l")` NOT `SomeComp([children], direction: "row", gap: "l")` — colon syntax is NOT supported and silently breaks',
          "7. Optional arguments can be omitted from the end"
        ]
        n = 8
        if flags[:bindings]
          lines << "#{n}. Declare mutable state with `$varName = defaultValue`. Components marked with `$binding` can read/write these. Undeclared $variables are auto-created with null default."
          n += 1
        end
        if flags[:supports_expressions]
          lines << "#{n}. String concatenation: `\"text\" + $var + \"more\"`"
          lines << "#{n + 1}. Dot member access: `query.field` reads a field; on arrays it extracts that field from every element"
          lines << "#{n + 2}. Index access: `arr[0]`, `data[index]`"
          lines << "#{n + 3}. Arithmetic operators: +, -, *, /, % (work on numbers; + is string concat when either side is a string)"
          lines << "#{n + 4}. Comparison: ==, !=, >, <, >=, <="
          lines << "#{n + 5}. Logical: &&, ||, ! (prefix)"
          lines << "#{n + 6}. Ternary: `condition ? valueIfTrue : valueIfFalse`"
          lines << "#{n + 7}. Parentheses for grouping: `(a + b) * c`"
        end
        lines << "- Strings use double quotes with backslash escaping"
        lines.join("\n")
      end

      def builtin_functions_section(custom, tool_calls)
        lines = Lang::Builtins::FUNCTION_DEFS.map { |d| function_line(d[:signature], d[:description]) } + custom
        <<~TEXT.chomp
          ## Built-in Functions

          Data functions prefixed with `@` to distinguish from components. These are the ONLY functions available — do NOT invent new ones.
          Use @-prefixed built-in functions (@Count, @Sum, @Avg, @Min, @Max, @Round) on #{tool_calls ? "Query results" : "data"}. Do NOT hardcode computed values.

          #{lines.join("\n")}

          Builtins compose — output of one is input to the next:
          `@Count(@Filter(data.rows, "field", "==", "val"))` for KPIs/chart values, `@Round(@Avg(data.rows.score), 1)`, `@Each(data.rows, "item", Comp(item.field))` for per-item rendering.
          Array pluck: `data.rows.field` extracts a field from every row → use with @Sum, @Avg, charts, tables.

          IMPORTANT @Each rule: The loop variable (e.g. "item") is ONLY available inside the @Each template expression. Always inline the template — do NOT extract it to a separate statement.
          CORRECT: `list = @Each(rows, "t", Comp(t.name))`
          WRONG: `item = Comp(t.name)` then `list = @Each(rows, "t", item)`, because t is undefined in item.
        TEXT
      end

      def query_section
        <<~TEXT.chomp
          ## Query — Live Data Fetching

          Fetch data from available tools. Returns defaults instantly, swaps in real data when it arrives.

          ```
          metrics = Query("tool_name", {arg1: value, arg2: $binding}, {defaultField: 0, defaultData: []}, refreshInterval?)
          ```

          - First arg: tool name (string)
          - Second arg: arguments object (may reference $bindings — re-fetches automatically on change)
          - Third arg: default data (rendered immediately before fetch resolves)
          - Fourth arg (optional): refresh interval in seconds (e.g. 30 for auto-refresh every 30s)
          - Use dot access on results: metrics.totalEvents, metrics.data.day (array pluck)
          - Query results must use regular identifiers: `metrics = Query(...)`, NOT `$metrics = Query(...)`
          - Manual refresh: `Button("Refresh", Action([@Run(query1), @Run(query2)]), "secondary")` — re-fetches the listed queries
          - Refresh all queries: create Action with @Run for each query
        TEXT
      end

      def mutation_section
        <<~TEXT.chomp
          ## Mutation — Write Operations

          Execute state-changing tool calls (create, update, delete). Unlike Query (auto-fetches on render), Mutation fires only on button click via Action.

          ```
          result = Mutation("tool_name", {arg1: $binding, arg2: "value"})
          ```

          - First arg: tool name (string)
          - Second arg: arguments object (evaluated with current $binding values at click time)
          - result.status: "idle" | "loading" | "success" | "error"
          - result.data: tool response on success
          - result.error: error message on failure
          - Mutation results use regular identifiers: `result = Mutation(...)`, NOT `$result`
          - Show loading state: `result.status == "loading" ? TextContent("Saving...") : null`
        TEXT
      end

      def builtin_steps(flags)
        Lang::Builtins::STEP_DEFS.select do |s|
          case s[:name]
          when "Run" then flags[:tool_calls]
          when "Set", "Reset" then flags[:bindings]
          else true
          end
        end
      end

      def action_section(flags, custom)
        steps = builtin_steps(flags).map { |s| "- #{function_line(s[:signature], s[:description])}" } + custom
        examples = []
        if flags[:tool_calls]
          examples << <<~TEXT.chomp
            Example — mutation + refresh + reset (PREFERRED pattern):
            ```
            $binding = "default"
            result = Mutation("tool_name", {field: $binding})
            data = Query("tool_name", {}, {rows: []})
            onSubmit = Action([@Run(result), @Run(data), @Reset($binding)])
            ```
          TEXT
        end
        examples << <<~TEXT.chomp
          Example — simple nav:
          ```
          viewBtn = Button("View", @OpenUrl("https://example.com"))
          ```
        TEXT
        rules = ['- An action can be assigned to a variable or inlined: Button("Go", onSubmit) and Button("Go", Action([...])) both work']
        if flags[:tool_calls]
          rules << "- If a @Run(mutation) step fails, remaining steps are skipped (halt on failure)"
          rules << "- @Run(queryRef) re-fetches the query (fire-and-forget, cannot fail)"
        end
        <<~TEXT.chomp
          #{ACTION_HEADER}

          An action wires a button click to operations. Pass one @-prefixed step bare, e.g. Button("Ask", @ToAssistant("Tell me more")). Put several steps in Action([...]), e.g. Button("Read", Action([@OpenUrl("https://example.com"), @ToAssistant("Summarize this page")])). Steps execute in order.
          Buttons without an action automatically send their label to the assistant (equivalent to @ToAssistant(label)).

          Available steps:
          #{steps.join("\n")}

          #{examples.join("\n\n")}

          #{rules.join("\n")}
        TEXT
      end

      def interactive_filters_section
        <<~'TEXT'.chomp
          ## Interactive Filters

          To let the user filter data with a dropdown:
          1. Declare a $variable with a default: `$dateRange = "14"`
          2. Create a Select with name, items, and binding: `Select("dateRange", [SelectItem("7", "Last 7 days"), ...], null, null, $dateRange)`
          3. Wrap in FormControl for a label: `FormControl("Date Range", Select(...))`
          4. Pass $dateRange in Query args: `Query("tool", {dateRange: $dateRange}, {defaults})`
          5. When the user changes the Select, $dateRange updates and the Query automatically re-fetches

          FILTER WIRING RULE: If a $binding filter is visible in the UI, EVERY relevant Query MUST reference that $binding in its args. Never show a filter dropdown while hardcoding the query args.

          Rules for $variables:
          - $variables hold simple values (strings or numbers), NOT arrays or objects
          - $variables must be bound to a Select/Input component via the value argument (last positional arg) to be interactive
          - Queries must use regular identifiers (NOT $variables): `metrics = Query(...)` not `$metrics = Query(...)`
          - **Auto-declare**: You do NOT need to explicitly declare $variables. If you use `$foo` without declaring it, the parser auto-creates `$foo = null`. You can still declare explicitly to set a default: `$days = "14"`

          ## Forms

          Simple form — no $bindings needed. Field values are managed internally by the Form via the name prop:
          ```
          contactForm = Form("contact", submitBtn, [nameField, emailField])
          nameField = FormControl("Name", Input("name", "Your name", "text", {required: true}))
          emailField = FormControl("Email", Input("email", "your@email.com", "email", {required: true, email: true}))
          submitBtn = Button("Submit")
          ```

          Use $bindings when you need to read field values elsewhere (in Action context, Query args, or conditionals). They are auto-declared:
          ```
          $role = "engineer"
          contactForm = Form("contact", submitBtn, [nameField, emailField, roleField])
          nameField = FormControl("Name", Input("name", "Enter your name", "text", {required: true}, $name))
          emailField = FormControl("Email", Input("email", "Enter your email", "email", {required: true, email: true}, $email))
          roleField = FormControl("Role", Select("role", [SelectItem("engineer", "Engineer"), SelectItem("designer", "Designer"), SelectItem("pm", "PM")], null, {required: true}, $role))
          submitBtn = Button("Submit")
          ```

          For form + mutation patterns (create, refresh, reset), see the Action section example above.

          IMPORTANT: Always add validation rules to form fields used with Mutations. Use OBJECT syntax: {required: true, email: true, minLength: 8}. The renderer shows error messages automatically and blocks submit when validation fails.
        TEXT
      end

      def edit_mode_section
        <<~TEXT.chomp
          ## Edit Mode

          The runtime merges by statement name: same name = replace, new name = append.
          Output ONLY statements that changed or are new. Everything else is kept automatically.

          ### Delete
          To remove a component, re-declare its parent without that component in the parent's children array. The removed component and any statements only it referenced are automatically garbage-collected.

          ### Patch size guide
          - Changing a title or label: 1 statement
          - Adding a component: 2-3 statements (the new component + parent update)
          - Removing a component: 1 statement (re-declare parent without the removed child)
          - Adding a filter + wiring to query: 3-5 statements
          - Restructuring into tabs: 5-10 statements

          ### Rules
          - Reuse existing statement names exactly — do not rename
          - Do NOT re-emit unchanged statements — the runtime keeps them
          - A typical edit patch is 1-10 statements, not 20+
          - If the existing code already satisfies the request, output only the root statement
          - NEVER output the entire program as a patch. Only output what actually changes
          - If you are about to output more than 10 statements, reconsider — most edits need fewer
        TEXT
      end

      def streaming_rules(root_name, flags)
        steps = ["1. `root = #{root_name}(...)` — UI shell appears immediately"]
        if flags[:supports_expressions]
          steps << "2. $variable declarations — state ready for bindings"
          steps << "3. Query statements — defaults resolve immediately so components render with data" if flags[:tool_calls]
          n = steps.length
          steps << "#{n + 1}. Component definitions — fill in with data already available"
          steps << "#{n + 2}. Data values — leaf content last"
        else
          steps << "2. Component definitions — fill in as they stream"
          steps << "3. Data values — leaf content last"
        end
        <<~TEXT.chomp
          ## Hoisting & Streaming (CRITICAL)

          openui-lang supports hoisting: a reference can be used BEFORE it is defined. The parser resolves all references after the full input is parsed.

          During streaming, the output is re-parsed on every chunk. Undefined references are temporarily unresolved and appear once their definitions stream in. This creates a progressive top-down reveal — structure first, then data fills in.

          **Recommended statement order for optimal streaming:**
          #{steps.join("\n")}

          Always write the root = #{root_name}(...) statement first so the UI shell appears immediately, even before child data has streamed in.
        TEXT
      end

      def inline_mode_section
        <<~TEXT.chomp
          ## Inline Mode

          You are in inline mode. You can respond in two ways:

          ### 1. Code response (when the user wants to CREATE or CHANGE the UI)
          Wrap openui-lang code in triple-backtick fences. You can include explanatory text before/after:

          Here's your dashboard:

          ```openui-lang
          root = RootComp([header, content])
          header = SomeHeader("Title")
          content = SomeContent("Hello world")
          ```

          I created a simple layout with a header.

          ### 2. Text-only response (when the user asks a QUESTION)
          If the user asks "what is this?", "explain the chart", "how does this work", etc. — respond with plain text. Do NOT output any openui-lang code. The existing dashboard stays unchanged.

          ### Rules
          - When the user asks for changes, output ONLY the changed/new statements in a fenced block
          - When the user asks a question, respond with text only — NO code. The dashboard stays unchanged.
          - The parser extracts code from fences automatically. Text outside fences is shown as chat.
        TEXT
      end

      def tool_workflow_section
        <<~TEXT.chomp
          ## Data Workflow

          When tools are available, follow this workflow:
          1. FIRST: Call the most relevant tool to inspect the real data shape before generating code
          2. Use Query() for READ operations (data that should stay live) — NEVER hardcode tool results as literal arrays or objects
          3. Use Mutation() for WRITE operations (create, update, delete) — triggered by button clicks via @Run(mutationRef)
          4. Use the real data from step 1 as condensed Query defaults (3-5 rows) so the UI renders immediately
          5. Use @-prefixed builtins (@Count, @Filter, @Sort, @Sum) on Query results for KPIs and aggregations — the runtime evaluates these live on every refresh
          6. Hardcoded arrays are ONLY for static display data (labels, options) where no tool exists

          WRONG — you called a tool and got data back, but you inlined the results:
          ```
          openCount = 2
          item1 = SomeComp("first item title")
          item2 = SomeComp("second item title")
          list = SomeList([item1, item2])
          chart = SomeChart(["A", "B"], [12, 8])
          ```
          This is static — it shows stale data and won't update. Creating item1, item2, item3... manually is ALWAYS wrong when a tool exists.

          RIGHT — use Query() for live data, Mutation() for writes, @builtins to derive values:
          ```
          data = Query("tool_name", {}, {rows: []})
          openCount = @Count(@Filter(data.rows, "field", "==", "value"))
          list = @Each(data.rows, "item", SomeComp(item.title, item.field))
          createResult = Mutation("create_tool", {title: $title})
          submitBtn = Button("Create", Action([@Run(createResult), @Run(data), @Reset($title)]))
          ```
          Everything derives from the Query — when data refreshes, the entire dashboard updates automatically.
        TEXT
      end

      def important_rules(root_name, flags)
        verify = [
          "1. root = #{root_name}(...) is the FIRST line (for optimal streaming).",
          "2. Every referenced name is defined. Every defined name (other than root) is reachable from root."
        ]
        verify << "3. Every Query result is referenced by at least one component." if flags[:tool_calls]
        if flags[:bindings]
          verify << "#{flags[:tool_calls] ? "4" : "3"}. Every $binding appears in at least one component or expression."
        end
        if flags[:tool_calls] && flags[:bindings]
          verify << "5. Every visible filter $binding appears in at least one Query args object."
        end
        <<~TEXT.chomp
          ## Important Rules
          - Choose components that best represent the content (tables for comparisons, charts for trends, forms for input, etc.)

          ## Final Verification
          Before finishing, walk your output and verify:
          #{verify.join("\n")}
        TEXT
      end

      # ── Tools ──────────────────────────────────────────────────────────────

      def json_schema_type_str(schema)
        schema = stringify(schema)
        case schema["type"]
        when "string"
          enum = schema["enum"]
          enum ? enum.map { |v| "\"#{v}\"" }.join(" | ") : "string"
        when "number", "integer" then "number"
        when "boolean" then "boolean"
        when "array"
          items = schema["items"]
          items ? "#{json_schema_type_str(items)}[]" : "any[]"
        when "object"
          props = schema["properties"]
          if props.is_a?(Hash) && !props.empty?
            required = schema["required"] || []
            "{" + props.map { |k, v| "#{k}#{required.include?(k) ? "" : "?"}: #{json_schema_type_str(v)}" }.join(", ") + "}"
          else
            "object"
          end
        else "any"
        end
      end

      def default_for_schema(schema)
        schema = stringify(schema)
        case schema["type"]
        when "string" then ""
        when "number", "integer" then 0
        when "boolean" then false
        when "array" then []
        when "object"
          props = schema["properties"]
          (props.is_a?(Hash) && !props.empty?) ? props.transform_values { |v| default_for_schema(v) } : {}
        else nil
        end
      end

      def stringify(obj)
        case obj
        when Hash then obj.to_h { |k, v| [k.to_s, stringify(v)] }
        when Array then obj.map { |v| stringify(v) }
        else obj
        end
      end

      def tool_signature(tool)
        args = ""
        input = tool["inputSchema"]
        if input.is_a?(Hash)
          props = input["properties"]
          required = input["required"] || []
          if props.is_a?(Hash) && !props.empty?
            args = props.map { |k, v| "#{k}#{required.include?(k) ? "" : "?"}: #{json_schema_type_str(v)}" }.join(", ")
          end
        end
        ret = tool["outputSchema"] ? " → #{json_schema_type_str(tool["outputSchema"])}" : ""
        line = "- #{tool["name"]}(#{args})#{ret}"
        line += "\n  #{tool["description"]}" if tool["description"]
        line
      end

      def tools_section(tools)
        tools = tools.map { |t| t.is_a?(String) ? t : stringify(t) }
        lines = ["## Available Tools", "",
          "Use these with Query() for read operations or Mutation() for write operations. The LLM decides which is appropriate based on the tool's purpose.", ""]
        strings, specs = tools.partition { |t| t.is_a?(String) }
        strings.each { |t| lines << "- #{t}" }
        specs.each { |t| lines << tool_signature(t) }
        with_output = specs.select { |t| t["outputSchema"] }
        unless with_output.empty?
          lines << ""
          lines << "### Default values for Query results"
          lines << ""
          lines << "Use these shapes as minimal Query defaults:"
          with_output.each { |t| lines << "- #{t["name"]}: `#{JSON.generate(default_for_schema(t["outputSchema"]))}`" }
        end
        lines << ""
        lines << "CRITICAL: Use ONLY the tools listed above in Query() and Mutation() calls. Do NOT invent or guess tool names. If the user asks for functionality that doesn't match any available tool, use realistic mock data instead of fabricating a tool call."
        lines.join("\n")
      end

      def component_signatures(spec, flags)
        components = spec["components"] || {}
        lines = ["## Component Signatures", "",
          "Arguments marked with ? are optional. Sub-components can be inline or referenced; prefer references for better streaming."]
        if flags[:uses_action_expression]
          all_steps = (builtin_steps(flags).map { |s| s[:name] } + (spec["actions"] || {}).keys).map { |n| "@#{n}" }
          lines << "Props typed `ActionExpression` accept one @step, or Action([@steps...]) for several. See the Action section for available steps (#{all_steps.join(", ")})."
          if components.values.any? { |c| RESTRICTED_SLOT.match?(c["signature"].to_s) }
            lines << "Props typed like `@OpenUrl | @ToAssistant` accept only the steps listed."
          end
        end
        uses_bindings = flags[:bindings] || components.values.any? { |c| c["signature"].to_s.include?("$binding") }
        lines << "Props marked `$binding<type>` accept a `$variable` reference for two-way binding." if uses_bindings

        format = ->(c) { c["description"] ? "#{c["signature"]} — #{c["description"]}" : c["signature"] }
        groups = spec["componentGroups"]
        if groups.is_a?(Array) && !groups.empty?
          grouped = []
          groups.each do |g|
            lines << ""
            lines << "### #{g["name"]}"
            (g["components"] || []).each do |name|
              next if grouped.include?(name)
              comp = components[name]
              next unless comp
              grouped << name
              lines << format.call(comp)
            end
            (g["notes"] || []).each { |note| lines << note }
          end
          ungrouped = components.keys - grouped
          unless ungrouped.empty?
            lines << ""
            lines << "### Other"
            ungrouped.each { |name| lines << format.call(components[name]) }
          end
        else
          lines << ""
          components.each_value { |c| lines << format.call(c) }
        end
        lines.join("\n")
      end
    end
  end
end
