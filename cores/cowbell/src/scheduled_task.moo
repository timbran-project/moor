object SCHEDULED_TASK
  name: "Scheduled Task"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for scheduled tasks. Tasks store: schedule_id, task_id, target, verb, args, run_at, recurring, interval.";
  override import_export_id = "scheduled_task";

  verb mk (this none this) owner: HACKER flags: "rxd"
    "Create a new scheduled task flyweight.";
    "Args: schedule_id, target, verb, args, run_at, recurring, [task_id], [interval]";
    if (length(args) < 6)
      raise(E_INVARG, "Usage: mk(schedule_id, target, verb, args, run_at, recurring, [task_id], [interval])");
    endif
    {schedule_id, target, verb_name, task_args, run_at, recurring, ?task_id = 0, ?interval = 0} = args;
    typeof(schedule_id) == INT || raise(E_TYPE, "Schedule ID must be integer");
    typeof(target) == OBJ || raise(E_TYPE, "Target must be object");
    typeof(verb_name) == STR || raise(E_TYPE, "Verb must be string");
    typeof(task_args) == LIST || raise(E_TYPE, "Args must be list");
    typeof(run_at) == INT || raise(E_TYPE, "Run_at must be timestamp");
    slots = ['schedule_id -> schedule_id, 'task_id -> task_id, 'target -> target, 'verb -> verb_name, 'args -> task_args, 'run_at -> run_at, 'recurring -> recurring];
    if (recurring)
      slots['interval] = interval;
    endif
    return toflyweight(this, slots);
  endverb

  verb schedule_id (this none this) owner: HACKER flags: "rxd"
    "Get schedule ID (scheduler's internal tracking ID).";
    return this.schedule_id;
  endverb

  verb task_id (this none this) owner: HACKER flags: "rxd"
    "Get MOO runtime task ID (from fork), or 0 if not yet executed.";
    return this.task_id;
  endverb

  verb target (this none this) owner: HACKER flags: "rxd"
    "Get task target object.";
    return this.target;
  endverb

  verb verb (this none this) owner: HACKER flags: "rxd"
    "Get task verb name.";
    return this.verb;
  endverb

  verb args (this none this) owner: HACKER flags: "rxd"
    "Get task arguments list.";
    return this.args;
  endverb

  verb run_at (this none this) owner: HACKER flags: "rxd"
    "Get task run time.";
    return this.run_at;
  endverb

  verb recurring (this none this) owner: HACKER flags: "rxd"
    "Check if task is recurring.";
    return this.recurring;
  endverb

  verb interval (this none this) owner: HACKER flags: "rxd"
    "Get recurring interval (only for recurring tasks).";
    return this.interval;
  endverb

  verb set_run_at (this none this) owner: HACKER flags: "rxd"
    "Update the run_at time for this task. Returns new flyweight.";
    {new_run_at} = args;
    typeof(new_run_at) == INT || raise(E_TYPE, "Run_at must be timestamp");
    "Create new flyweight with updated run_at";
    new_slots = this.slots;
    new_slots['run_at] = new_run_at;
    return toflyweight(this.delegate, new_slots);
  endverb

  verb set_task_id (this none this) owner: HACKER flags: "rxd"
    "Update the MOO runtime task_id for this task. Returns new flyweight.";
    {new_task_id} = args;
    typeof(new_task_id) == INT || raise(E_TYPE, "Task ID must be integer");
    "Create new flyweight with updated task_id";
    new_slots = this.slots;
    new_slots['task_id] = new_task_id;
    return toflyweight(this.delegate, new_slots);
  endverb
endobject