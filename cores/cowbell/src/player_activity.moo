object PLAYER_ACTIVITY
  name: "$player_activity"
  parent: THING
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  override import_export_hierarchy = 0;
  override import_export_id = "player_activity";

  verb make_entry (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Build an activity entry map.";
    {kind, task_id, label} = args;
    return ['kind -> kind, 'task_id -> task_id, 'label -> label, 'started_at -> time()];
  endverb

  verb task_id_of (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Extract task id from an activity entry.";
    {entry} = args;
    return `entry['task_id] ! ANY => 0';
  endverb

  verb kind_of (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Extract kind from an activity entry.";
    {entry} = args;
    return `entry['kind] ! ANY => ""';
  endverb

  verb cancel_entry (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Cancel the task referenced by an activity entry.";
    {entry} = args;
    task_id = this:task_id_of(entry);
    if (!(typeof(task_id) == TYPE_INT && task_id > 0))
      return 0;
    endif
    `kill_task(task_id) ! ANY';
    return 1;
  endverb

  verb description_of (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return display description for an activity entry.";
    {entry} = args;
    label = `entry['label] ! ANY => ""';
    if (typeof(label) == TYPE_STR && label != "")
      return label;
    endif
    kind = this:kind_of(entry);
    if (kind == 'walk)
      return "walking";
    elseif (kind != "" && kind != $nothing)
      return tostr(kind);
    endif
    return "that";
  endverb
endobject
