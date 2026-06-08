object HEADLESS_SCHEDULER_SCENARIOS
  name: "Headless Scheduler Runtime Scenarios"
  parent: ROOT
  owner: HACKER
  readable: true

  property scheduler_callback_value (owner: HACKER, flags: "r") = 0;

  override description = "Headless runtime scenarios for scheduler behaviour without player I/O.";
  override import_export_hierarchy = {"tests", "headless"};
  override import_export_id = "headless_scheduler_scenarios";

  verb test_headless_scheduler_callback (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: a scheduled callback executes and cleans up its task record.";
    this.scheduler_callback_value = 0;
    $scheduler:stop();
    schedule_id = $scheduler:schedule_after(1, this, "scheduler_callback");
    try
      deadline = time() + 6;
      while (time() <= deadline && this.scheduler_callback_value == 0)
        suspend(1);
      endwhile
      $test_utils:assert_eq(this.scheduler_callback_value, 1, "scheduled callback should run");
      $test_utils:assert_false($scheduler:is_scheduled(this, "scheduler_callback"), "completed one-shot callback should not remain scheduled");
    finally
      $scheduler:cancel(schedule_id);
      this.scheduler_callback_value = 0;
    endtry
    return true;
  endverb

  verb test_headless_scheduler_recurring_cancel (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: a recurring callback runs repeatedly and can be cancelled cleanly.";
    this.scheduler_callback_value = 0;
    $scheduler:stop();
    schedule_id = $scheduler:schedule_every(1, this, "scheduler_recurring_callback");
    try
      deadline = time() + 8;
      while (time() <= deadline && this.scheduler_callback_value < 2)
        suspend(1);
      endwhile
      $test_utils:assert_true(this.scheduler_callback_value >= 2, "recurring callback should run more than once");
      $test_utils:assert_eq($scheduler:is_scheduled(this, "scheduler_recurring_callback"), schedule_id, "recurring callback should remain scheduled before cancel");
      $test_utils:assert_true($scheduler:cancel(schedule_id), "cancel should remove recurring callback");
      $test_utils:assert_false($scheduler:is_scheduled(this, "scheduler_recurring_callback"), "cancelled recurring callback should not remain scheduled");
    finally
      $scheduler:cancel(schedule_id);
      this.scheduler_callback_value = 0;
    endtry
    return true;
  endverb

  verb scheduler_callback (this none this) owner: HACKER flags: "rxd"
    "Callback used by the one-shot scheduler runtime scenario.";
    this.scheduler_callback_value = 1;
    return true;
  endverb

  verb scheduler_recurring_callback (this none this) owner: HACKER flags: "rxd"
    "Callback used by the recurring scheduler runtime scenario.";
    this.scheduler_callback_value = this.scheduler_callback_value + 1;
    return true;
  endverb
endobject
