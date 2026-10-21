# frozen_string_literal: true

class DemoController < ApplicationController
  include ActionController::Live

  def index
    @prompt = DemoRun::DEFAULT_PROMPT
  end

  def create
    run = DemoRun.create(params[:prompt])
    redirect_to demo_run_path(run.id)
  end

  def show
    @run = DemoRun.find(params[:id]) or return redirect_to(demo_path)
    @live = DemoStreamer.new(@run).live?
  end

  # Server-Sent Events consumed by <turbo-stream-source>. No ActionCable needed.
  def events
    run = DemoRun.find(params[:id])
    return head(:not_found) unless run
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
    response.headers["Last-Modified"] = Time.now.httpdate
    DemoStreamer.new(run).each_event { |sse| response.stream.write(sse) }
  rescue ActionController::Live::ClientDisconnected, IOError
    # the browser went away
  ensure
    response.stream.close
  end

  # A static render of the canned program, no streaming.
  def sample
    @program = DemoStreamer::CANNED
  end
end
