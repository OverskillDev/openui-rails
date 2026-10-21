# frozen_string_literal: true

# In-memory demo state; the dummy app has no database.
class DemoRun
  DEFAULT_PROMPT = "Compare these 3 plans for a 6-person team: Starter is $19/month for 1 seat, " \
                   "Team is $49/month for 5 seats, Business is $99/month for 25 seats and adds SSO."

  STORE = {}
  MUTEX = Mutex.new

  attr_reader :id, :prompt

  def self.create(prompt)
    run = new(SecureRandom.hex(6), prompt.to_s.strip.presence || DEFAULT_PROMPT)
    MUTEX.synchronize do
      STORE[run.id] = run
      STORE.shift while STORE.size > 50
    end
    run
  end

  def self.find(id)
    MUTEX.synchronize { STORE[id] }
  end

  def initialize(id, prompt)
    @id = id
    @prompt = prompt
  end

  def mount_id
    "answer-#{id}"
  end
end
