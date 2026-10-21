# frozen_string_literal: true

require_relative "rails_test_helper"
require "rails/generators/test_case"
require "generators/openui/install/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests Openui::InstallGenerator
  destination File.expand_path("../dummy/tmp/generator", __dir__)
  setup :prepare_destination

  test "writes the initializer and the library" do
    run_generator
    assert_file "config/initializers/openui.rb" do |content|
      assert_match(/OpenUI::Rails\.configure/, content)
      assert_match(/config\.library = -> \{ OpenuiLibrary\.instance \}/, content)
    end
    assert_file "app/libraries/openui_library.rb" do |content|
      assert_match(/module OpenuiLibrary/, content)
      assert_match(/\.extend\(id: "dummy", version: "1\.0\.0"\) do/, content)
    end
    assert_no_file "app/views/openui/components/_card.html.erb"
  end

  test "copies the starter partials with --partials" do
    run_generator %w[--partials]
    %w[stack card text table col key_value callout chart].each do |name|
      assert_file "app/views/openui/components/_#{name}.html.erb"
    end
  end

  test "the generated library file evaluates to a working library" do
    run_generator
    load File.join(destination_root, "app/libraries/openui_library.rb")
    lib = OpenuiLibrary.instance
    assert_equal "dummy", lib.id
    assert_equal "Stack", lib.root
    assert_includes OpenuiLibrary.prompt_options.keys, :examples
  ensure
    Object.send(:remove_const, :OpenuiLibrary) if defined?(OpenuiLibrary)
  end
end
