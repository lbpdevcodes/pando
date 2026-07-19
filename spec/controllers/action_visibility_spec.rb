# frozen_string_literal: true

# Charming invokes every declared action with public_send — keys, commands,
# timers, task completions, and task PROGRESS events all dispatch from outside
# the controller. An action accidentally defined under `private` crashes the
# live app the first time its event fires (the journey suite runs under the
# inline executor, where hub/timer events never fire, so only this sweep
# catches it).
RSpec.describe "Controller action visibility" do
  def declared_actions(controller)
    actions = []
    actions.concat(controller.key_bindings.values)
    actions.concat(controller.command_bindings.map(&:value).select { |v| v.is_a?(Symbol) })
    actions.concat(controller.timer_bindings.values.map(&:action))
    actions.concat(controller.task_bindings.values.map(&:action))
    actions.concat(controller.task_progress_bindings.values.map(&:action))
    actions.uniq
  end

  [Pando::ChatController, Pando::OnboardingController].each do |controller|
    it "exposes every bound action on #{controller} publicly" do
      not_public = declared_actions(controller).reject do |action|
        controller.public_method_defined?(action)
      end

      expect(not_public).to be_empty,
        "these bound actions are not public on #{controller}: #{not_public.inspect}"
    end
  end
end
