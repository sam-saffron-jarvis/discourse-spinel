# frozen_string_literal: true
# TEST-only inspection of the real constructor's fields, on both runtimes.
class LatestLayoutProbe
  def self.readonly_state(controller)
    {readonly: controller.instance_variable_get(:@readonly_mode),
      staff_writes_only: controller.instance_variable_get(:@staff_writes_only_mode)}
  end

  def self.capture(controller)
    preloader = controller.instance_variable_get(:@application_layout_preloader)
    return {allocated: false} if preloader.nil?
    guardian = preloader.instance_variable_get(:@guardian)
    {allocated: preloader.is_a?(ApplicationLayoutPreloader),
      theme_id: preloader.instance_variable_get(:@theme_id),
      theme_target: preloader.instance_variable_get(:@theme_target).to_s,
      login_method: preloader.instance_variable_get(:@login_method),
      guardian_anonymous: guardian.anonymous?,
      preloaded_empty: preloader.instance_variable_get(:@preloaded).empty?}
  end
end
