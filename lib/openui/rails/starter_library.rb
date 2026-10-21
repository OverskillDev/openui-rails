# frozen_string_literal: true

module OpenUI
  module Rails
    # A small static library for data-heavy answers: layout, text, a table,
    # key-value pairs, a callout and a chart. No forms, no actions, no raw
    # HTML. Copy and adapt it with `bin/rails generate openui:install`.
    module StarterLibrary
      module_function

      def build(id: "openui-starter", version: OpenUI::VERSION)
        OpenUI::Library.define(id: id, version: version, root: "Stack") do
          component "Stack", description: "Lays out children top to bottom (column, the default) or side by side (row).",
            renders: "openui/components/stack" do
            arg :children, list(component)
            arg :direction, enum("column", "row"), default: "column"
          end

          component "Card", description: "A titled surface that groups related content. Use for one subject per card.",
            renders: "openui/components/card" do
            arg :title, string
            arg :children, list(component), optional: true
            arg :subtitle, string, optional: true
          end

          component "Text", description: "A run of plain text. heading for a section title, caption for small secondary text.",
            renders: "openui/components/text" do
            arg :text, string
            arg :variant, enum("body", "heading", "caption"), default: "body"
          end

          component "Table", description: "A table built from columns. Each Col carries its header and its cell values in row order.",
            renders: "openui/components/table" do
            arg :columns, list(component("Col"))
            arg :caption, string, optional: true
          end

          component "Col", description: "One table column: a header label and the cell values, one per row. Right-align numbers. sort marks the column the rows are ordered by.",
            renders: "openui/components/col" do
            arg :label, string
            arg :data, list(any)
            arg :align, enum("left", "right"), default: "left"
            arg :sort, enum("asc", "desc"), optional: true
          end

          component "KeyValue", description: "Label and value pairs for facts about one thing (specs, totals, settings).",
            renders: "openui/components/key_value" do
            arg :items, list(object(label: string, value: any))
            arg :title, string, optional: true
          end

          component "Callout", description: "A highlighted note. info for context, tip for advice, warning for caveats, danger for risks or losses.",
            renders: "openui/components/callout" do
            arg :text, string
            arg :variant, enum("info", "tip", "warning", "danger"), default: "info"
            arg :title, string, optional: true
          end

          component "Chart", description: "A bar, line or pie chart. labels are the x axis (or the pie slices); each series has a name and one number per label. Use bar to compare, line for trends over time, pie for shares of a whole (first series only).",
            renders: "openui/components/chart" do
            arg :labels, list(string)
            arg :series, list(object(name: string, data: list(number)))
            arg :variant, enum("bar", "line", "pie"), default: "bar"
            arg :title, string, optional: true
          end

          group "Layout", components: %w[Stack Card]
          group "Content", components: %w[Text Callout KeyValue], notes: ["- Prefer KeyValue over a two-column Table for facts about one item."]
          group "Data", components: %w[Table Col Chart], notes: ["- Define each Col as its own statement so columns stream in one at a time."]
        end
      end

      # Prompt options tuned for the starter library.
      def prompt_options
        {
          additional_rules: [
            "Put the direct answer first: a Text heading or a Callout, then the supporting Table, KeyValue or Chart.",
            "Numbers in Col data and Chart series are plain numbers, not strings with units; put units in the label."
          ],
          examples: [
            <<~OUI.chomp
              root = Stack([title, table, note])
              title = Text("Three plans compared", "heading")
              table = Table([plan, price, seats])
              plan = Col("Plan", ["Starter", "Team", "Business"])
              price = Col("Price per month (USD)", [19, 49, 99], "right")
              seats = Col("Seats", [1, 5, 25], "right")
              note = Callout("Team is the best value for groups under 10.", "tip")
            OUI
          ]
        }
      end
    end
  end
end
