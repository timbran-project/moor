object SCHEDULED_TASK
  name: "Scheduled Task"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for scheduled tasks. Tasks store: schedule_id, task_id, target, verb, args, run_at, recurring, interval.";
  override import_export_hierarchy = {"scheduler"};
  override import_export_id = "scheduled_task";

  method mk owner: HACKER
    "Create a new scheduled task flyweight.";
    "Args: schedule_id, target, verb, args, run_at, recurring, [task_id], [interval]";
    if (length(args) < 6)
      raise(E_INVARG, "Usage: mk(schedule_id, target, verb, args, run_at, recurring, [task_id], [interval])");
    endif
    {schedule_id, target, verb_name, task_args, run_at, recurring, ?task_id = 0, ?interval = 0} = args;
    typeof(schedule_id) == TYPE_INT || raise(E_TYPE, "Schedule ID must be integer");
    typeof(target) == TYPE_OBJ || raise(E_TYPE, "Target must be object");
    typeof(verb_name) == TYPE_STR || raise(E_TYPE, "Verb must be string");
    typeof(task_args) == TYPE_LIST || raise(E_TYPE, "Args must be list");
    typeof(run_at) == TYPE_INT || raise(E_TYPE, "Run_at must be timestamp");
    slots = ['schedule_id -> schedule_id, 'task_id -> task_id, 'target -> target, 'verb -> verb_name, 'args -> task_args, 'run_at -> run_at, 'recurring -> recurring];
    if (recurring)
      slots['interval] = interval;
    endif
    return toflyweight(this, slots);
  endmethod

  method schedule_id owner: HACKER
    "Get schedule ID (scheduler's internal tracking ID).";
    return this.schedule_id;
  endmethod

  method task_id owner: HACKER
    "Get MOO runtime task ID (from fork), or 0 if not yet executed.";
    return this.task_id;
  endmethod

  method target owner: HACKER
    "Get task target object.";
    return this.target;
  endmethod

  method verb owner: HACKER
    "Get task verb name.";
    return this.verb;
  endmethod

  method args owner: HACKER
    "Get task arguments list.";
    return this.args;
  endmethod

  method run_at owner: HACKER
    "Get task run time.";
    return this.run_at;
  endmethod

  method recurring owner: HACKER
    "Check if task is recurring.";
    return this.recurring;
  endmethod

  method interval owner: HACKER
    "Get recurring interval (only for recurring tasks).";
    return this.interval;
  endmethod

  method set_run_at owner: HACKER
    "Update the run_at time for this task. Returns new flyweight.";
    {new_run_at} = args;
    typeof(new_run_at) == TYPE_INT || raise(E_TYPE, "Run_at must be timestamp");
    "Create new flyweight with updated run_at";
    new_slots = this.slots;
    new_slots['run_at] = new_run_at;
    return toflyweight(this.delegate, new_slots);
  endmethod

  method set_task_id owner: HACKER
    "Update the MOO runtime task_id for this task. Returns new flyweight.";
    {new_task_id} = args;
    typeof(new_task_id) == TYPE_INT || raise(E_TYPE, "Task ID must be integer");
    "Create new flyweight with updated task_id";
    new_slots = this.slots;
    new_slots['task_id] = new_task_id;
    return toflyweight(this.delegate, new_slots);
  endmethod
endobject
