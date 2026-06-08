object HEADLESS_SCHEDULER_SCENARIOS
  name: "Headless Scheduler Runtime Scenarios"
  parent: ROOT
  owner: HACKER
  readable: true

  property scheduler_callback_value (owner: HACKER, flags: "r") = 0;
  property scheduler_error_value (owner: HACKER, flags: "r") = 0;

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

  verb test_headless_scheduler_cancel_before_run (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: cancelling a pending callback prevents execution and clears its task record.";
    this.scheduler_callback_value = 0;
    $scheduler:stop();
    schedule_id = $scheduler:schedule_after(2, this, "scheduler_callback");
    try
      $test_utils:assert_true($scheduler:cancel(schedule_id), "cancel should remove pending callback");
      $test_utils:assert_false($scheduler:is_scheduled(this, "scheduler_callback"), "cancelled callback should not be scheduled");
      $test_utils:assert_eq($scheduler:when_scheduled(schedule_id), 0, "cancelled callback should not have a run time");
      suspend(3);
      $test_utils:assert_eq(this.scheduler_callback_value, 0, "cancelled callback should not run");
    finally
      $scheduler:cancel(schedule_id);
      this.scheduler_callback_value = 0;
    endtry
    return true;
  endverb

  verb test_headless_scheduler_error_isolation (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: an erroring scheduled callback does not block another ready callback.";
    this.scheduler_callback_value = 0;
    this.scheduler_error_value = 0;
    $scheduler:stop();
    error_id = $scheduler:schedule_after(1, this, "scheduler_error_callback");
    ok_id = $scheduler:schedule_after(1, this, "scheduler_callback");
    try
      deadline = time() + 6;
      while (time() <= deadline && this.scheduler_callback_value == 0)
        suspend(1);
      endwhile
      $test_utils:assert_eq(this.scheduler_error_value, 1, "erroring callback should have started");
      $test_utils:assert_eq(this.scheduler_callback_value, 1, "sibling callback should run despite scheduled task error");
      $test_utils:assert_false($scheduler:is_scheduled(this, "scheduler_error_callback"), "completed erroring callback should be cleaned up");
      $test_utils:assert_false($scheduler:is_scheduled(this, "scheduler_callback"), "completed sibling callback should be cleaned up");
    finally
      $scheduler:cancel(error_id);
      $scheduler:cancel(ok_id);
      this.scheduler_callback_value = 0;
      this.scheduler_error_value = 0;
    endtry
    return true;
  endverb

  verb test_headless_scheduler_stop_cleans_pending_tasks (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: stopping the scheduler clears pending task records.";
    this.scheduler_callback_value = 0;
    $scheduler:stop();
    first_id = $scheduler:schedule_after(10, this, "scheduler_callback");
    second_id = $scheduler:schedule_after(10, this, "scheduler_recurring_callback");
    $test_utils:assert_true($scheduler:is_scheduled(this, "scheduler_callback"), "first pending callback should be scheduled");
    $test_utils:assert_true($scheduler:is_scheduled(this, "scheduler_recurring_callback"), "second pending callback should be scheduled");
    $test_utils:assert_true($scheduler:stop(), "stop should stop a running scheduler");
    $test_utils:assert_false($scheduler:is_scheduled(this, "scheduler_callback"), "stop should clear first pending callback");
    $test_utils:assert_false($scheduler:is_scheduled(this, "scheduler_recurring_callback"), "stop should clear second pending callback");
    $test_utils:assert_eq($scheduler:when_scheduled(first_id), 0, "stop should clear first run time");
    $test_utils:assert_eq($scheduler:when_scheduled(second_id), 0, "stop should clear second run time");
    this.scheduler_callback_value = 0;
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

  verb scheduler_error_callback (this none this) owner: HACKER flags: "rxd"
    "Callback used by the scheduler error-isolation runtime scenario.";
    this.scheduler_error_value = 1;
    raise(E_INVARG, "intentional headless scheduler callback error");
  endverb
endobject
