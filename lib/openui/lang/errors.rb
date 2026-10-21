# frozen_string_literal: true

module OpenUI
  module Lang
    # The error object of language.md section 8.3. +to_h+ is the wire shape,
    # ready to send back to the model.
    Error = Struct.new(:source, :code, :message, :statement_id, :component, :path, :hint, :severity,
      keyword_init: true) do
      def warning?
        severity == "warning"
      end

      def fatal?
        %w[parse-failed parse-exception].include?(code) || (code == "no-root" && !warning?)
      end

      def to_h
        {
          "source" => source, "code" => code, "message" => message,
          "statementId" => statement_id, "component" => component, "path" => path,
          "hint" => hint, "severity" => severity
        }.compact
      end
    end

    # Raised only for programming errors in a Library definition, never for
    # model output.
    class LibraryError < StandardError; end
  end
end
