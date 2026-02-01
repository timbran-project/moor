object HOUSEKEEPING
  name: "Housekeeping"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  property idle_threshold (owner: ARCH_WIZARD, flags: "rc") = 3600;
  property schedule_id (owner: ARCH_WIZARD, flags: "rc") = 38;
  property sweep_interval (owner: ARCH_WIZARD, flags: "rc") = 3000;
  property sweep_msgs (owner: ARCH_WIZARD, flags: "rc") = HOUSEKEEPING_SWEEP_MSGS;

  override import_export_hierarchy = {"initial"};
  override import_export_id = "housekeeping";

  verb sweep (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Sweep disconnected players back to their home rooms.";
    "Called periodically by the scheduler.";
    caller_perms().wizard || caller == $scheduler || raise(E_PERM);
    connected = connected_players();
    threshold = this.idle_threshold;
    now = time();
    swept = {};
    for p in (players())
      if (p in connected)
        continue;
      endif
      disconnected_at = `p.last_disconnected ! E_PROPNF => 0';
      if (disconnected_at == 0 || now - disconnected_at < threshold)
        continue;
      endif
      home = `p.home ! E_PROPNF => #-1';
      if (typeof(home) != TYPE_OBJ || !valid(home))
        server_log("Player with no home: " + tostr(p) + " (" + p.name + ") .. resetting to $login.default_home");
        p.home = $login.default_home;
        home = p.home;
      endif
      if (p.location == home)
        continue;
      endif
      old_loc = p.location;
      try
        p:moveto(home);
        swept = {@swept, {old_loc, p}};
        msg = "Housekeeping quietly escorted you back to " + home.name + " while you were away.";
        p:tell($event:mk_info(this, msg):with_audience('utility));
        suspend(0);
      except e (ANY)
      endtry
    endfor
    rooms_done = {};
    total_swept = length(swept);
    for entry in (swept)
      {room, _} = entry;
      if (room in rooms_done)
        continue;
      endif
      rooms_done = {@rooms_done, room};
      names = {};
      for e in (swept)
        if (e[1] == room)
          names = {@names, e[2].name};
        endif
      endfor
      if (!valid(room) || !respond_to(room, 'announce) || length(names) == 0)
        continue;
      endif
      if (length(names) == 1)
        msg = "Housekeeping quietly escorts " + names[1] + " away to bed.";
      elseif (length(names) <= 4)
        msg = "Housekeeping quietly escorts " + names:english_list() + " away to bed.";
      else
        shown = names[1..3];
        rest = length(names) - 3;
        msg = "Housekeeping quietly escorts " + shown:english_list() + ", and " + tostr(rest) + " others away to bed.";
      endif
      `room:announce($event:mk_info(this, msg):with_audience('utility)) ! ANY';
    endfor
    total_swept > 0 && `server_log(tostr("Housekeeping swept ", total_swept, " sleeping player(s) home.")) ! E_PERM';
    return total_swept;
  endverb

  verb start (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Start the housekeeping sweep schedule.";
    caller_perms().wizard || raise(E_PERM);
    existing = $scheduler:is_scheduled(this, "sweep");
    if (existing)
      this.schedule_id = existing;
      return "Already running (schedule_id: " + tostr(existing) + ")";
    endif
    this.schedule_id = $scheduler:schedule_every(this.sweep_interval, this, "sweep", {});
    return "Housekeeping started (schedule_id: " + tostr(this.schedule_id) + ", interval: " + tostr(this.sweep_interval) + "s)";
  endverb

  verb stop (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Stop the housekeeping sweep schedule.";
    caller_perms().wizard || raise(E_PERM);
    existing = $scheduler:is_scheduled(this, "sweep");
    if (!existing)
      this.schedule_id = 0;
      return "Not running.";
    endif
    $scheduler:cancel(existing);
    this.schedule_id = 0;
    return "Housekeeping stopped (was schedule_id: " + tostr(existing) + ")";
  endverb
endobject