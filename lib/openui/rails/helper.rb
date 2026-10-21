# frozen_string_literal: true

module OpenUI
  module Rails
    # View helpers mixed into ActionView.
    module Helper
      # Render OpenUI Lang text or a ParseResult inside a mount element the
      # progressive updates can target.
      #
      #   <%= openui_render(@program, library: MyLibrary, mount_id: "answer-#{@message.id}") %>
      def openui_render(source, library: OpenUI::Rails.library, mount_id: "openui", placeholders: OpenUI::Rails.placeholders,
        limits: OpenUI::Lang::Limits.default, html_options: {})
        result = source.is_a?(OpenUI::Lang::ParseResult) ? source : library.parse(source.to_s, limits: limits, placeholders: placeholders)
        renderer = Renderer.new(library, view_context: self, mount_id: mount_id, placeholders: placeholders)
        content_tag(:div, renderer.render(result), {id: mount_id, class: "openui-root"}.merge(html_options))
      end

      # An empty mount for a response that will stream in.
      def openui_mount(mount_id, html_options: {})
        content_tag(:div, "", {id: mount_id, class: "openui-root"}.merge(html_options))
      end

      def openui_stylesheet_tag(**options)
        stylesheet_link_tag("openui", **options)
      end

      # Inline SVG bar or line chart used by the starter Chart partial.
      # +series+ is [{"name" => String, "data" => [Numeric]}]. No JavaScript.
      def openui_chart_svg(labels:, series:, variant: "bar", width: 560, height: 240)
        labels = Array(labels).first(60).map(&:to_s)
        series = Array(series).first(8).map do |s|
          s = s.is_a?(Hash) ? s : {}
          data = Array(s["data"]).first(60).map { |v| openui_chart_number(v) }
          {name: s["name"].to_s, data: data}
        end
        points = [labels.length, series.map { |s| s[:data].length }.max || 0].max
        return content_tag(:p, "No data", class: "openui-chart__empty") if points.zero? || series.empty?
        return openui_pie_svg(labels: labels, data: series.first[:data], size: height) if variant == "pie"

        max = series.flat_map { |s| s[:data] }.compact.max || 0
        min = [0, series.flat_map { |s| s[:data] }.compact.min || 0].min
        max = 1 if max <= min
        pad_l = 40
        pad_b = 28
        pad_t = 12
        pad_r = 12
        plot_w = width - pad_l - pad_r
        plot_h = height - pad_t - pad_b
        y_for = ->(v) { pad_t + plot_h - ((v - min).to_f / (max - min) * plot_h) }

        content_tag(:svg, viewBox: "0 0 #{width} #{height}", class: "openui-chart__svg openui-chart__svg--#{variant}",
          role: "img", "aria-label": "#{variant} chart") do
          parts = []
          parts << tag.line(x1: pad_l, y1: y_for.call(0), x2: width - pad_r, y2: y_for.call(0), class: "openui-chart__axis")
          [min, max].uniq.each do |v|
            parts << content_tag(:text, Lang::Builtins.js_string(v), x: pad_l - 6, y: y_for.call(v) + 4, class: "openui-chart__tick", "text-anchor": "end")
          end
          if variant == "line"
            series.each_with_index do |s, si|
              coords = s[:data].each_with_index.filter_map do |v, i|
                next if v.nil?
                x = pad_l + (points == 1 ? plot_w / 2.0 : i * plot_w.to_f / (points - 1))
                "#{x.round(1)},#{y_for.call(v).round(1)}"
              end
              parts << tag.polyline(points: coords.join(" "), fill: "none", class: "openui-chart__line openui-chart__series-#{si}")
            end
          else
            group_w = plot_w.to_f / points
            bar_w = [group_w / (series.length + 1), 2].max
            series.each_with_index do |s, si|
              s[:data].each_with_index do |v, i|
                next if v.nil?
                x = pad_l + i * group_w + bar_w * (si + 0.5)
                y_top = y_for.call([v, 0].max)
                h = (y_for.call([v, 0].min) - y_top).abs
                parts << tag.rect(x: x.round(1), y: y_top.round(1), width: bar_w.round(1), height: h.round(1),
                  class: "openui-chart__bar openui-chart__series-#{si}")
              end
            end
          end
          labels.each_with_index do |label, i|
            x = pad_l + (variant == "line" ? (points == 1 ? plot_w / 2.0 : i * plot_w.to_f / (points - 1)) : (i + 0.5) * plot_w.to_f / points)
            parts << content_tag(:text, label, x: x.round(1), y: height - 8, class: "openui-chart__label", "text-anchor": "middle")
          end
          safe_join(parts)
        end
      end

      # Pie slices from one series: label i gets data[i]. Zero, negative and
      # missing values are left out; slice colors cycle through the 8 series colors.
      def openui_pie_svg(labels:, data:, size: 240)
        slices = data.each_with_index.filter_map { |v, i| [i, v] if v && v.positive? }
        total = slices.sum { |_, v| v }
        return content_tag(:p, "No data", class: "openui-chart__empty") if total.zero?

        c = size / 2.0
        r = c - 4
        angle = -Math::PI / 2
        content_tag(:svg, viewBox: "0 0 #{size} #{size}", class: "openui-chart__svg openui-chart__svg--pie", role: "img", "aria-label": "pie chart") do
          parts = slices.map do |i, v|
            klass = "openui-chart__slice openui-chart__series-#{i % 8}"
            title = content_tag(:title, "#{labels[i]}: #{Lang::Builtins.js_string(v)}")
            next content_tag(:circle, title, cx: c, cy: c, r: r, class: klass) if slices.length == 1
            sweep = v.to_f / total * 2 * Math::PI
            x1, y1 = c + r * Math.cos(angle), c + r * Math.sin(angle)
            angle += sweep
            x2, y2 = c + r * Math.cos(angle), c + r * Math.sin(angle)
            d = format("M%.1f,%.1f L%.1f,%.1f A%.1f,%.1f 0 %d 1 %.1f,%.1f Z", c, c, x1, y1, r, r, sweep > Math::PI ? 1 : 0, x2, y2)
            content_tag(:path, title, d: d, class: klass)
          end
          safe_join(parts)
        end
      end

      # A small Markdown subset for the Markdown component: paragraphs, # to ###
      # headings, - and 1. lists, **bold**, *italic*, `code`. The text is
      # escaped first and only these tags are added around escaped runs, so
      # model text can never produce other markup. No links, images or HTML.
      def openui_markdown(text)
        blocks = []
        para = []
        list = nil
        flush = lambda do
          if para.any?
            blocks << content_tag(:p, safe_join(para.map { |l| openui_markdown_inline(l) }, tag.br), class: "leading-7")
            para = []
          end
          if list
            klass = list[:tag] == :ol ? "list-decimal space-y-1 pl-5" : "list-disc space-y-1 pl-5"
            blocks << content_tag(list[:tag], safe_join(list[:items].map { |i| content_tag(:li, openui_markdown_inline(i)) }), class: klass)
            list = nil
          end
        end
        text.to_s.gsub("\r\n", "\n").split("\n").each do |line|
          if line.strip.empty?
            flush.call
          elsif (m = line.match(/\A(\#{1,3})\s+(.+)\z/))
            flush.call
            size = {1 => "text-lg", 2 => "text-base", 3 => "text-sm"}[m[1].length]
            blocks << content_tag(:"h#{m[1].length + 2}", openui_markdown_inline(m[2]), class: "#{size} font-semibold text-gray-900 dark:text-gray-100")
          elsif (m = line.match(/\A\s*(?:([-*])|\d+[.)])\s+(.+)\z/))
            kind = m[1] ? :ul : :ol
            flush.call if para.any? || (list && list[:tag] != kind)
            list ||= {tag: kind, items: []}
            list[:items] << m[2]
          else
            flush.call if list
            para << line.strip
          end
        end
        flush.call
        safe_join(blocks)
      end

      def openui_markdown_inline(text)
        parts = ERB::Util.html_escape(text.to_s).to_str.split("`", -1)
        html = parts.each_with_index.map do |part, i|
          if i.odd? && i < parts.length - 1
            %(<code class="rounded bg-gray-100 px-1 py-0.5 font-mono text-[0.85em] dark:bg-gray-800">#{part}</code>)
          else
            part = "`#{part}" if i.odd?
            part.gsub(/\*\*(?=\S)(.+?)(?<=\S)\*\*/, '<strong class="font-semibold">\1</strong>')
              .gsub(/(?<![*\w])\*(?=\S)(.+?)(?<=\S)\*(?![*\w])/, '<em>\1</em>')
          end
        end
        html.join.html_safe # rubocop:disable Rails/OutputSafety -- escaped above, only fixed tags added
      end

      # An image URL a component may load: https, or a path on the host
      # ("/..."). Anything else (http, data:, javascript:, protocol-relative)
      # is nil and the component renders its placeholder instead.
      def openui_safe_src(src)
        src = src.to_s.strip
        src if src.match?(%r{\Ahttps://[^\s"'<>]+\z}) || src.match?(%r{\A/(?!/)[^\s"'<>]*\z})
      end

      # Up to two initials for an avatar: "Ada Lovelace" -> "AL".
      def openui_initials(name)
        words = name.to_s.scan(/[[:alnum:]]+/)
        letters = words.length > 1 ? [words.first[0], words.last[0]] : [words.first.to_s[0, 2]]
        letters.join.upcase
      end

      # Inline Lucide icons (https://lucide.dev, ISC) for the components and
      # the catalog page. Unknown names render nothing.
      ICONS = {
        "arrow-up" => '<path d="m5 12 7-7 7 7"/><path d="M12 19V5"/>',
        "arrow-down" => '<path d="M12 5v14"/><path d="m19 12-7 7-7-7"/>',
        "check" => '<path d="M20 6 9 17l-5-5"/>',
        "circle" => '<circle cx="12" cy="12" r="10"/>',
        "circle-check" => '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
        "chevron-down" => '<path d="m6 9 6 6 6-6"/>',
        "copy" => '<rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
        "external-link" => '<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
        "image" => '<rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/>',
        "message-square" => '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
        "minus" => '<path d="M5 12h14"/>',
        "moon" => '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>',
        "sun" => '<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>',
        "trending-up" => '<polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/><polyline points="16 7 22 7 22 13"/>',
        "trending-down" => '<polyline points="22 17 13.5 8.5 8.5 13.5 2 7"/><polyline points="16 17 22 17 22 11"/>'
      }.freeze

      def openui_icon(name, size: 16, **attrs)
        paths = ICONS[name.to_s] or return "".html_safe
        options = {xmlns: "http://www.w3.org/2000/svg", width: size, height: size, viewBox: "0 0 24 24", fill: "none",
                   stroke: "currentColor", "stroke-width": 2, "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": true}
        content_tag(:svg, paths.html_safe, options.merge(attrs)) # rubocop:disable Rails/OutputSafety -- constant markup
      end

      def openui_chart_number(value)
        case value
        when Numeric then value.to_f.finite? ? value.to_f : nil
        when String then Float(value, exception: false)
        else nil
        end
      end
    end
  end
end
