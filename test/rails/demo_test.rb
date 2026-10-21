# frozen_string_literal: true

require_relative "rails_test_helper"

class DemoTest < ActionDispatch::IntegrationTest
  test "static sample renders the canned program" do
    get sample_path
    assert_response :success
    assert_select "div#sample.openui-root table.openui-table tbody tr", 3
    assert_select "#sample-note aside.openui-callout--tip"
    assert_select "link[href*='openui']"
  end

  test "demo form creates a run and the run page mounts a stream source" do
    get demo_path
    assert_response :success
    assert_select "form textarea"
    post demo_path, params: {prompt: "Compare three plans"}
    assert_response :redirect
    follow_redirect!
    id = request.path.split("/").last
    assert_select "turbo-stream-source[src='#{demo_events_path(id)}']"
    assert_select "div#answer-#{id}.openui-root"
    assert_select "pre#program-#{id}"
  end

  test "events endpoint streams turbo streams over sse" do
    run = DemoRun.create("Compare three plans")
    get demo_events_path(run.id)
    assert_response :success
    assert_equal "text/event-stream", response.media_type
    body = response.body
    assert_match(/data: <turbo-stream action="update" target="answer-#{run.id}">/, body)
    assert_match(/data: <turbo-stream action="replace" target="answer-#{run.id}-title">/, body)
    assert_match(/data: <turbo-stream action="update" target="program-#{run.id}">/, body)
    assert_match(/no errors/, body)
    assert body.scan("<turbo-stream").length > 5
  end

  test "unknown run is a 404" do
    get demo_events_path("nope")
    assert_response :not_found
  end
end
