# frozen_string_literal: true

module OpenUI
  module Rails
    # The starter library plus the components shown on the catalog page:
    # structure, rich text, KPIs and status, form controls, buttons with
    # actions, lists and media. The partials use plain Tailwind utility
    # classes, so a host that renders them needs Tailwind to see the gem's
    # app/views (see CATALOG.md). Form controls and buttons render inert:
    # nothing in openui-rails runs an action yet; the plan is on the element
    # as data-openui-action for a host to wire up.
    module CatalogLibrary
      module_function

      def build(id: "openui-catalog", version: OpenUI::VERSION)
        StarterLibrary.build.extend(id: id, version: version) do
          component "Section", description: "A titled region of the answer that groups several components under one heading.",
            renders: "openui/components/section" do
            arg :title, string
            arg :children, list(component)
            arg :description, string, optional: true
          end

          component "Divider", description: "A horizontal rule between groups of content, with an optional short label.",
            renders: "openui/components/divider" do
            arg :label, string, optional: true
          end

          component "Markdown", description: "Formatted prose: paragraphs, # headings, - and 1. lists, **bold**, *italic* and `code`. No links, images or HTML.",
            renders: "openui/components/markdown" do
            arg :text, string
          end

          component "Metric", description: "One headline number (KPI) with a label. unit $ € or £ goes before the number, % right after it, any other unit after a space. delta is the percent change versus the prior period.",
            renders: "openui/components/metric" do
            arg :label, string
            arg :value, number
            arg :unit, string, optional: true
            arg :delta, number, optional: true
            arg :caption, string, optional: true
          end

          component "Badge", description: "A short status label. success for done or healthy, warning for at risk, danger for failed or blocked, info for in progress.",
            renders: "openui/components/badge" do
            arg :text, string
            arg :tone, enum("neutral", "info", "success", "warning", "danger"), default: "neutral"
          end

          component "List", description: "A bulleted or numbered list of short text items.",
            renders: "openui/components/list" do
            arg :items, list(string)
            arg :variant, enum("bullet", "ordered"), default: "bullet"
          end

          component "Checklist", description: "Tasks with done or not-done state, for plans, onboarding steps and requirements.",
            renders: "openui/components/checklist" do
            arg :items, list(object(label: string, done: optional(boolean)))
            arg :title, string, optional: true
          end

          component "Timeline", description: "Events in time order, each with a title, an optional time and an optional detail line.",
            renders: "openui/components/timeline" do
            arg :items, list(object(title: string, time: optional(string), text: optional(string)))
          end

          component "Form", description: "Groups input controls and a submit Button. name identifies the form to the host.",
            renders: "openui/components/form" do
            arg :name, string
            arg :children, list(component)
            arg :title, string, optional: true
          end

          component "Input", description: "A labelled text field. type textarea for long text.",
            renders: "openui/components/input" do
            arg :name, string
            arg :label, string, optional: true
            arg :placeholder, string, optional: true
            arg :type, enum("text", "email", "number", "date", "textarea"), default: "text"
            arg :value, string, optional: true
          end

          component "Select", description: "A labelled dropdown with one choice from options.",
            renders: "openui/components/select" do
            arg :name, string
            arg :options, list(string)
            arg :label, string, optional: true
            arg :value, string, optional: true
          end

          component "Checkbox", description: "A single yes or no choice with a label.",
            renders: "openui/components/checkbox" do
            arg :name, string
            arg :label, string
            arg :checked, boolean, optional: true
          end

          component "Button", description: "A button that runs an action: @ToAssistant to continue the conversation, @OpenUrl to open a page. primary for the main action, secondary or ghost for the rest.",
            renders: "openui/components/button" do
            arg :label, string
            arg :action, action, optional: true
            arg :variant, enum("primary", "secondary", "ghost"), default: "primary"
          end

          component "Image", description: "An image with alt text and an optional caption. Without an https src it renders as a labelled image slot.",
            renders: "openui/components/image" do
            arg :alt, string
            arg :src, string, optional: true
            arg :caption, string, optional: true
          end

          component "Avatar", description: "A person or team: initials (or an https photo), a name and an optional role line.",
            renders: "openui/components/avatar" do
            arg :name, string
            arg :subtitle, string, optional: true
            arg :src, string, optional: true
          end

          group "Structure", components: %w[Section Divider]
          group "Rich text", components: %w[Markdown List Checklist Timeline]
          group "Status", components: %w[Metric Badge], notes: ["- Put several Metric in a row Stack for a KPI strip."]
          group "Forms and actions", components: %w[Form Input Select Checkbox Button],
            notes: ["- Put the controls and one submit Button inside a Form.", "- Use @ToAssistant for follow-up questions, @OpenUrl for links."]
          group "Media", components: %w[Image Avatar]
        end
      end

      # The components this library adds to the starter library, in definition order.
      def added_components
        build.component_names - StarterLibrary.build.component_names
      end

      def prompt_options
        StarterLibrary.prompt_options
      end
    end
  end
end
