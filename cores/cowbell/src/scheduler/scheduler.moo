object SCHEDULER
  name: "Task Scheduler"
  parent: ROOT
  owner: HACKER
  readable: true

  property loop_task_id (owner: HACKER, flags: "r") = 0;
  property next_schedule_id (owner: HACKER, flags: "r") = 1;
  property running (owner: HACKER, flags: "r") = false;
  property sweep_task_id (owner: HACKER, flags: "r") = 0;

  override description = "Task scheduler for executing verbs on objects at specified times or intervals. Each scheduled task is stored in its own property (scheduled_task_N) to avoid transaction conflicts.";
  override import_export_hierarchy = {"scheduler"};
  override import_export_id = "scheduler";

  verb schedule_after (this none this) owner: HACKER flags: "rxd"
    "Schedule a verb to run after N seconds: schedule_after(seconds, object, verb, [args]).";
    if (length(args) < 3)
      raise(E_INVARG, "Usage: schedule_after(seconds, object, verb, [args])");
    endif
    {delay, target, verb_name, ?task_args = {}} = args;
    typeof(delay) in {TYPE_INT, TYPE_FLOAT} || raise(E_TYPE, "Delay must be number");
    typeof(target) == TYPE_OBJ || raise(E_TYPE, "Target must be object");
    valid(target) || raise(E_INVARG, "Target must be valid object");
    typeof(verb_name) in {TYPE_STR, TYPE_SYM} || raise(E_TYPE, "Verb must be string or symbol");
    verb_name = tostr(verb_name);
    typeof(task_args) == TYPE_LIST || raise(E_TYPE, "Args must be list");
    run_at = time() + delay;
    schedule_id = this.next_schedule_id;
    this.next_schedule_id = schedule_id + 1;
    task = $scheduled_task:mk(schedule_id, target, verb_name, task_args, run_at, false);
    "Store task in its own property to avoid transaction conflicts";
    prop_name = "scheduled_task_" + tostr(schedule_id);
    add_property(this, prop_name, task, {this.owner, "r"});
    this:_ensure_running();
    return schedule_id;
  endverb

  verb schedule_at (this none this) owner: HACKER flags: "rxd"
    "Schedule a verb to run at a specific timestamp: schedule_at(timestamp, object, verb, [args]).";
    if (length(args) < 3)
      raise(E_INVARG, "Usage: schedule_at(timestamp, object, verb, [args])");
    endif
    {run_at, target, verb_name, ?task_args = {}} = args;
    typeof(run_at) == TYPE_INT || raise(E_TYPE, "Timestamp must be integer");
    typeof(target) == TYPE_OBJ || raise(E_TYPE, "Target must be object");
    valid(target) || raise(E_INVARG, "Target must be valid object");
    typeof(verb_name) in {TYPE_STR, TYPE_SYM} || raise(E_TYPE, "Verb must be string or symbol");
    verb_name = tostr(verb_name);
    typeof(task_args) == TYPE_LIST || raise(E_TYPE, "Args must be list");
    if (run_at <= time())
      raise(E_INVARG, "Timestamp must be in the future");
    endif
    schedule_id = this.next_schedule_id;
    this.next_schedule_id = schedule_id + 1;
    task = $scheduled_task:mk(schedule_id, target, verb_name, task_args, run_at, false);
    "Store task in its own property to avoid transaction conflicts";
    prop_name = "scheduled_task_" + tostr(schedule_id);
    add_property(this, prop_name, task, {this.owner, "r"});
    this:_ensure_running();
    return schedule_id;
  endverb

  verb schedule_every (this none this) owner: HACKER flags: "rxd"
    "Schedule a recurring task: schedule_every(interval, object, verb, [args]).";
    "Interval can be: INT/FLOAT (seconds), STR (HH:MM:SS for daily), LIST {min, range} for random.";
    if (length(args) < 3)
      raise(E_INVARG, "Usage: schedule_every(interval, object, verb, [args])");
    endif
    {interval, target, verb_name, ?task_args = {}} = args;
    typeof(target) == TYPE_OBJ || raise(E_TYPE, "Target must be object");
    valid(target) || raise(E_INVARG, "Target must be valid object");
    typeof(verb_name) in {TYPE_STR, TYPE_SYM} || raise(E_TYPE, "Verb must be string or symbol");
    verb_name = tostr(verb_name);
    typeof(task_args) == TYPE_LIST || raise(E_TYPE, "Args must be list");
    "Validate interval format";
    interval_type = typeof(interval);
    if (interval_type == TYPE_INT || interval_type == TYPE_FLOAT)
      interval > 0 || raise(E_INVARG, "Interval must be positive");
      next_run = time() + interval;
    elseif (interval_type == TYPE_STR)
      "Parse HH:MM:SS format";
      next_run = interval:parse_time_of_day();
    elseif (interval_type == TYPE_LIST && length(interval) == 2)
      {min_delay, range_delay} = interval;
      typeof(min_delay) in {TYPE_INT, TYPE_FLOAT} || raise(E_TYPE, "Random interval min must be number");
      typeof(range_delay) in {TYPE_INT, TYPE_FLOAT} || raise(E_TYPE, "Random interval range must be number");
      min_delay > 0 || raise(E_INVARG, "Random interval min must be positive");
      range_delay >= 0 || raise(E_INVARG, "Random interval range must be non-negative");
      next_run = time() + min_delay + random(toint(range_delay));
    else
      raise(E_TYPE, "Interval must be number, HH:MM:SS string, or {min, range} list");
    endif
    schedule_id = this.next_schedule_id;
    this.next_schedule_id = schedule_id + 1;
    task = $scheduled_task:mk(schedule_id, target, verb_name, task_args, next_run, true, 0, interval);
    "Store task in its own property to avoid transaction conflicts";
    prop_name = "scheduled_task_" + tostr(schedule_id);
    add_property(this, prop_name, task, {this.owner, "r"});
    this:_ensure_running();
    return schedule_id;
  endverb

  verb cancel (this none this) owner: HACKER flags: "rxd"
    "Cancel a scheduled task by schedule ID. Returns true if found and cancelled.";
    {schedule_id} = args;
    typeof(schedule_id) == TYPE_INT || raise(E_TYPE, "Schedule ID must be integer");
    prop_name = "scheduled_task_" + tostr(schedule_id);
    try
      this.(prop_name);
      delete_property(this, prop_name);
      return true;
    except (E_PROPNF)
      return false;
    endtry
  endverb

  verb is_scheduled (this none this) owner: HACKER flags: "rxd"
    "Check if a specific verb on an object is scheduled. Returns schedule ID or 0.";
    {target, verb_name} = args;
    typeof(target) == TYPE_OBJ || raise(E_TYPE, "Target must be object");
    typeof(verb_name) in {TYPE_STR, TYPE_SYM} || raise(E_TYPE, "Verb must be string or symbol");
    verb_name = tostr(verb_name);
    for prop_name in (properties(this))
      prop_str = tostr(prop_name);
      if (prop_str:starts_with("scheduled_task_"))
        task = this.(prop_name);
        if (task.target == target && task.verb == verb_name)
          return task.schedule_id;
        endif
      endif
    endfor
    return 0;
  endverb

  verb when_scheduled (this none this) owner: HACKER flags: "rxd"
    "Get the next run time for a scheduled task by ID. Returns timestamp or 0 if not found.";
    {schedule_id} = args;
    typeof(schedule_id) == TYPE_INT || raise(E_TYPE, "Schedule ID must be integer");
    prop_name = "scheduled_task_" + tostr(schedule_id);
    try
      return this.(prop_name).run_at;
    except (E_PROPNF)
      return 0;
    endtry
  endverb

  verb list_tasks (this none this) owner: HACKER flags: "rxd"
    "Return list of all scheduled tasks (as flyweights).";
    tasks = {};
    for prop_name in (properties(this))
      prop_str = tostr(prop_name);
      if (prop_str:starts_with("scheduled_task_"))
        tasks = {@tasks, this.(prop_name)};
      endif
    endfor
    return tasks;
  endverb

  verb start (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Start the scheduler loop. Called automatically when tasks are added.";
    caller == #0 || caller_perms().wizard || raise(E_PERM);
    if (this.running && valid_task(this.running))
      return false;
    endif
    this:_log("Starting...");
    fork loop (1)
      this:_run_loop();
    endfork
    this.running = loop;
    this.loop_task_id = loop;
    return true;
  endverb

  verb resume_if_needed (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Resume scheduler if there are persisted tasks. Called on server startup.";
    caller == #0 || caller_perms().wizard || raise(E_PERM);
    if (this.running && valid_task(this.running))
      return false;
    endif
    this:_log("Resuming...");
    "Count persisted tasks";
    task_count = 0;
    for prop in (properties(this))
      prop_str = tostr(prop);
      if (prop_str:starts_with("scheduled_task_"))
        task_count = task_count + 1;
      endif
    endfor
    if (task_count > 0)
      this:start();
      this:_log("Resumed with " + tostr(task_count) + " persisted tasks");
      "Start periodic sweep loop and run initial sweep";
      this:_start_sweep_loop();
      this:sweep();
      return true;
    endif
    return false;
  endverb

  verb stop (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Stop the scheduler loop and clear all tasks.";
    caller_perms().wizard || raise(E_PERM);
    if (!this.running || !valid_task(this.running))
      this.running = 0;
      return false;
    endif
    if (this.running)
      `kill_task(this.running) ! ANY';
      this.running = 0;
    endif
    this.loop_task_id = 0;
    if (this.sweep_task_id)
      `kill_task(this.sweep_task_id) ! ANY';
      this.sweep_task_id = 0;
    endif
    "Clear all scheduled tasks";
    for prop in (properties(this))
      prop_str = tostr(prop);
      if (prop_str:starts_with("scheduled_task_"))
        delete_property(this, prop);
      endif
    endfor
    return true;
  endverb

  verb sweep (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Sweep scheduled tasks and verify their task IDs are still queued. Clears stale IDs.";
    "Get currently queued tasks (requires wizard perms)";
    queued = queued_tasks();
    "Extract task IDs from queued tasks";
    active_task_ids = {};
    for task_info in (queued)
      "task_info[1] is the task ID";
      active_task_ids = {@active_task_ids, task_info[1]};
    endfor
    "Check scheduled tasks for stale task IDs and clean them up";
    stale_count = 0;
    for prop_name in (properties(this))
      prop_str = tostr(prop_name);
      if (!prop_str:starts_with("scheduled_task_"))
        continue;
      endif
      task = this.(prop_name);
      "Check if task has a system task ID";
      if (task.task_id != 0)
        "Verify task ID is still in queue";
        if (!(task.task_id in active_task_ids))
          stale_count = stale_count + 1;
          this:_log("Clearing stale task ID: schedule_id=" + tostr(task.schedule_id) + " task_id=" + tostr(task.task_id) + " target=" + tostr(task.target) + ":" + task.verb);
          "Clear the stale task_id";
          task = task:set_task_id(0);
          this.(prop_name) = task;
        endif
      endif
    endfor
    return stale_count;
  endverb

  verb _sweep_loop (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal: Periodic sweep loop running every 5 minutes.";
    caller == this || raise(E_PERM);
    while (this.running)
      try
        suspend(300);
        this:sweep();
      except e (ANY)
        this:_log("Sweep error: " + tostr(e));
      endtry
    endwhile
  endverb

  verb _ensure_running (this none this) owner: HACKER flags: "rxd"
    "Internal: Ensure scheduler loop is running.";
    caller == this || raise(E_PERM);
    if (!this.running || !valid_task(this.running))
      fork loop (1)
        this:_run_loop();
      endfork
      this.running = loop;
      this.loop_task_id = loop;
      "Start sweep loop";
      this:_start_sweep_loop();
    endif
  endverb

  verb _start_sweep_loop (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal: Start the periodic sweep loop.";
    caller == this || raise(E_PERM);
    if (this.sweep_task_id == 0)
      fork sweep_loop (1)
        this:_sweep_loop();
      endfork
      this.sweep_task_id = sweep_loop;
    endif
  endverb

  verb _run_loop (this none this) owner: HACKER flags: "rxd"
    "Internal: Main scheduler loop that processes tasks.";
    caller == this || raise(E_PERM);
    while (this.running)
      try
        this:_process_tasks();
        "Sleep for 1 second between checks";
        suspend(1);
      except e (ANY)
        "Log errors but keep running";
        this:_log("Scheduler error: " + toliteral(e));
      endtry
    endwhile
  endverb

  verb _process_tasks (this none this) owner: HACKER flags: "rxd"
    "Internal: Check and execute ready tasks.";
    caller == this || raise(E_PERM);
    now = time();
    task_count = 0;
    for prop_name in (properties(this))
      prop_str = tostr(prop_name);
      if (!prop_str:starts_with("scheduled_task_"))
        continue;
      endif
      task_count = task_count + 1;
      task = this.(prop_name);
      if (task.run_at <= now)
        "Execute this task via wizard helper";
        this:_execute_task(task.schedule_id, task.target, task.verb, task.args, task.recurring);
        "Handle recurring tasks";
        if (task.recurring)
          next_run = this:_calculate_next_run(task.interval, now);
          task = task:set_run_at(next_run);
          this.(prop_name) = task;
        else
          "One-time task completed - remove it";
          delete_property(this, prop_name);
          task_count = task_count - 1;
        endif
      endif
    endfor
    "Stop scheduler if no tasks remain";
    if (task_count == 0)
      this.running = 0;
    endif
  endverb

  verb _execute_task (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal: Execute a scheduled task with proper permissions.";
    caller == this || raise(E_PERM);
    {schedule_id, target, verb_name, task_args, recurring} = args;
    "Fork execution to avoid blocking scheduler, and start in new transaction.";
    fork forked_task_id (0)
      try
        set_task_perms(target);
        target:(verb_name)(@task_args);
      except e (ANY)
        this:_log("Scheduled task error: " + tostr(target) + ":" + verb_name + " => " + toliteral(e));
      endtry
      "Clear task_id for recurring tasks after execution completes";
      if (recurring)
        try
          prop_name = "scheduled_task_" + tostr(schedule_id);
          task = $scheduler.(prop_name);
          task = task:set_task_id(0);
          $scheduler.(prop_name) = task;
        except e (ANY)
          "Task property may have been deleted, ignore";
        endtry
      endif
    endfork
    "Store the forked task_id in the task property";
    try
      prop_name = "scheduled_task_" + tostr(schedule_id);
      task = this.(prop_name);
      task = task:set_task_id(forked_task_id);
      this.(prop_name) = task;
    except e (ANY)
      "Task property may have been deleted, ignore";
    endtry
  endverb

  verb _log (this none this) owner: ARCH_WIZARD flags: "rxd"
    {message} = args;
    caller == this || caller.wizard || raise(E_PERM);
    server_log("SCHEDULER(" + tostr(this) + ") " + message);
  endverb

  verb _calculate_next_run (this none this) owner: HACKER flags: "rxd"
    "Internal: Calculate next run time for recurring task.";
    caller == this || raise(E_PERM);
    {interval, current_time} = args;
    interval_type = typeof(interval);
    if (interval_type == TYPE_INT || interval_type == TYPE_FLOAT)
      return current_time + interval;
    elseif (interval_type == TYPE_STR)
      return interval:parse_time_of_day();
    elseif (interval_type == TYPE_LIST)
      {min_delay, range_delay} = interval;
      return current_time + min_delay + random(toint(range_delay));
    endif
    raise(E_TYPE, "Invalid interval type");
  endverb

  verb test_schedule_after (this none this) owner: HACKER flags: "rxd"
    "Test scheduling a task to run after a delay.";
    "Clean up any leftover properties from previous test runs";
    for prop in (properties(this))
      prop_str = tostr(prop);
      if (prop_str:starts_with("scheduled_task_"))
        delete_property(this, prop);
      endif
    endfor
    "Schedule a test task";
    start_time = time();
    schedule_id = this:schedule_after(2, this, "test_executed");
    schedule_id > 0 || raise(E_ASSERT, "Failed to schedule task");
    "Verify task property exists";
    prop_name = "scheduled_task_" + tostr(schedule_id);
    try
      task = this.(prop_name);
    except (E_PROPNF)
      raise(E_ASSERT, "Task property not found");
    endtry
    task.target == this || raise(E_ASSERT, "Wrong target");
    task.verb == "test_executed" || raise(E_ASSERT, "Wrong verb");
    task.recurring == false || raise(E_ASSERT, "Should not be recurring");
    "Verify scheduler is running";
    this.running || raise(E_ASSERT, "Scheduler should be running");
    "Clean up";
    this:cancel(schedule_id);
  endverb

  verb test_schedule_at (this none this) owner: HACKER flags: "rxd"
    "Test scheduling a task at a specific time.";
    "Clean up any leftover properties from previous test runs";
    for prop in (properties(this))
      prop_str = tostr(prop);
      if (prop_str:starts_with("scheduled_task_"))
        delete_property(this, prop);
      endif
    endfor
    future_time = time() + 10;
    schedule_id = this:schedule_at(future_time, this, "test_executed");
    schedule_id > 0 || raise(E_ASSERT, "Failed to schedule task");
    "Verify run time";
    run_at = this:when_scheduled(schedule_id);
    run_at == future_time || raise(E_ASSERT, "Wrong run time: " + tostr(run_at) + " vs " + tostr(future_time));
    "Clean up";
    this:cancel(schedule_id);
  endverb

  verb test_cancel (this none this) owner: HACKER flags: "rxd"
    "Test cancelling scheduled tasks.";
    "Clean up any leftover properties from previous test runs";
    for prop in (properties(this))
      prop_str = tostr(prop);
      if (prop_str:starts_with("scheduled_task_"))
        delete_property(this, prop);
      endif
    endfor
    schedule_id = this:schedule_after(10, this, "test_executed");
    schedule_id > 0 || raise(E_ASSERT, "Failed to schedule task");
    "Cancel should return true";
    result = this:cancel(schedule_id);
    result == true || raise(E_ASSERT, "Cancel should return true");
    "Verify task property is gone";
    prop_name = "scheduled_task_" + tostr(schedule_id);
    try
      this.(prop_name);
      raise(E_ASSERT, "Task property should be removed");
    except (E_PROPNF)
      "Property correctly removed";
    endtry
    "Cancelling again should return false";
    result = this:cancel(schedule_id);
    result == false || raise(E_ASSERT, "Second cancel should return false");
  endverb

  verb test_is_scheduled (this none this) owner: HACKER flags: "rxd"
    "Test checking if a verb is scheduled.";
    "Clean up any leftover properties from previous test runs";
    for prop in (properties(this))
      prop_str = tostr(prop);
      if (prop_str:starts_with("scheduled_task_"))
        delete_property(this, prop);
      endif
    endfor
    "Should return 0 when not scheduled";
    result = this:is_scheduled(this, "nonexistent_verb");
    result == 0 || raise(E_ASSERT, "Should return 0 for unscheduled verb");
    "Schedule a task";
    schedule_id = this:schedule_after(10, this, "test_verb");
    "Should return schedule ID when scheduled";
    result = this:is_scheduled(this, "test_verb");
    result == schedule_id || raise(E_ASSERT, "Should return schedule ID");
    "Clean up";
    this:cancel(schedule_id);
  endverb

  verb test_sweep (this none this) owner: HACKER flags: "rxd"
    "Test sweep verb for stale task ID detection.";
    "Clean up any leftover properties from previous test runs";
    for prop in (properties(this))
      prop_str = tostr(prop);
      if (prop_str:starts_with("scheduled_task_"))
        delete_property(this, prop);
      endif
    endfor
    "Sweep should return 0 when there are no tasks";
    result = this:sweep();
    result == 0 || raise(E_ASSERT, "Sweep should return 0 with no tasks");
    "Schedule a task and sweep again";
    schedule_id = this:schedule_after(10, this, "test_executed");
    result = this:sweep();
    result == 0 || raise(E_ASSERT, "Sweep should return 0 for scheduled tasks without task_ids");
    "Clean up";
    this:cancel(schedule_id);
  endverb

  verb test_list_tasks (this none this) owner: HACKER flags: "rxd"
    "Test listing scheduled tasks.";
    "Start with clean slate - remove all scheduled_task_* properties";
    for prop in (properties(this))
      prop_str = tostr(prop);
      if (prop_str:starts_with("scheduled_task_"))
        delete_property(this, prop);
      endif
    endfor
    "Schedule multiple tasks";
    sched1 = this:schedule_after(10, this, "test_verb1");
    sched2 = this:schedule_after(20, this, "test_verb2");
    "List should contain both";
    task_list = this:list_tasks();
    length(task_list) == 2 || raise(E_ASSERT, "Should have 2 tasks, got " + tostr(length(task_list)));
    "Verify task info is present";
    found1 = false;
    found2 = false;
    for task in (task_list)
      if (task.schedule_id == sched1)
        found1 = true;
        task.verb == "test_verb1" || raise(E_ASSERT, "Wrong verb for task1");
      elseif (task.schedule_id == sched2)
        found2 = true;
        task.verb == "test_verb2" || raise(E_ASSERT, "Wrong verb for task2");
      endif
    endfor
    found1 && found2 || raise(E_ASSERT, "Tasks not found in list");
    "Clean up";
    this:cancel(sched1);
    this:cancel(sched2);
  endverb

  verb test_validation (this none this) owner: HACKER flags: "rxd"
    "Test input validation for schedule verbs.";
    "Test invalid object rejection";
    try
      this:schedule_after(10, #-1, "test");
      raise(E_ASSERT, "Should reject invalid object");
    except (E_INVARG)
      "Expected - invalid object rejected";
    endtry
    "Test symbol verb name acceptance";
    schedule_id = this:schedule_after(10, this, 'test_executed);
    schedule_id > 0 || raise(E_ASSERT, "Should accept symbol verb name");
    "Verify task was created with string verb name";
    prop_name = "scheduled_task_" + tostr(schedule_id);
    try
      task = this.(prop_name);
      typeof(task.verb) == TYPE_STR || raise(E_ASSERT, "Verb should be stored as string");
    except (E_PROPNF)
      raise(E_ASSERT, "Task property should exist");
    endtry
    "Clean up";
    this:cancel(schedule_id);
  endverb

  verb test_executed (this none this) owner: HACKER flags: "rxd"
    "Placeholder verb for testing execution.";
    return true;
  endverb
endobject
