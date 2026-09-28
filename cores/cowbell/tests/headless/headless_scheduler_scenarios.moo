object HEADLESS_SCHEDULER_SCENARIOS
  name: "Headless Native Schedule Scenarios"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Native schedule lifecycle scenarios for housekeeping and Henri.";
  override import_export_hierarchy = {"tests", "headless"};
  override import_export_id = "headless_scheduler_scenarios";

  method test_headless_housekeeping_native_lifecycle owner: ARCH_WIZARD
    "Housekeeping starts once, remains recurring after empty sweeps, and cancels future firings.";
    const housekeeping = create($housekeeping, $arch_wizard, 2);
    try
      housekeeping.schedule_id = 0;
      housekeeping.sweep_interval = 0.1;
      housekeeping:start();
      const id = housekeeping.schedule_id;
      housekeeping:start();
      $test_utils:assert_eq(housekeeping.schedule_id, id, "duplicate start must retain one schedule");
      const deadline = time() + 5;
      "Commit native registration before querying runtime diagnostics.";
      suspend(0);
      let info = schedule_info(id);
      while (time() <= deadline && info["run_count"] == 0)
        "Commit registration and wait for an actual housekeeping sweep.";
        suspend(0.1);
        info = schedule_info(id);
      endwhile
      $test_utils:assert_true(info["run_count"] > 0, "native sweep must execute");
      $test_utils:assert_eq(info["target"], housekeeping, "schedule targets the fixture");
      $test_utils:assert_false(info["adaptive"], "sweep count must not change the recurrence");
      $test_utils:assert_false(info["pass_elapsed"], "sweep argument contract remains unchanged");
      $test_utils:assert_true(schedule_valid(id), "an empty sweep must not retire the recurrence");
      housekeeping:stop();
      "Commit cancellation before checking the runtime schedule store.";
      suspend(0);
      $test_utils:assert_false(schedule_valid(id), "stop must cancel future sweeps");
      $test_utils:assert_eq(housekeeping.schedule_id, 0, "stop clears the stored ID");
    finally
      valid(housekeeping) && housekeeping:stop();
      valid(housekeeping) && housekeeping:destroy();
    endtry
    return true;
  endmethod

  method test_headless_housekeeping_stale_id owner: ARCH_WIZARD
    "An objdef-style stale ID does not prevent a new native housekeeping schedule.";
    const housekeeping = create($housekeeping, $arch_wizard, 2);
    try
      housekeeping.schedule_id = 999999;
      housekeeping:start();
      $test_utils:assert_true(schedule_valid(housekeeping.schedule_id), "start replaces a stale ID");
      $test_utils:assert_true(housekeeping.schedule_id != 999999, "the stale ID must be replaced");
      housekeeping:stop();
      housekeeping:stop();
    finally
      valid(housekeeping) && housekeeping:stop();
      valid(housekeeping) && housekeeping:destroy();
    endtry
    return true;
  endmethod

  method test_headless_henri_native_lifecycle owner: ARCH_WIZARD
    "Henri creates six owner-authorized schedules, repairs stale IDs, and cancels them all.";
    const henri = create($henri, $hacker, 2);
    const recording_player = this:_recording_player();
    player = recording_player;
    try
      henri.scheduled_behaviours = ["grooming" -> 999999];
      henri:start_behaviours();
      const ids = mapvalues(henri.scheduled_behaviours);
      $test_utils:assert_eq(length(ids), 6, "all six behaviours must have native schedules");
      "Commit registration before inspecting native schedule diagnostics.";
      suspend(0);
      for id in (ids)
        const info = schedule_info(id);
        $test_utils:assert_eq(info["target"], henri, "native schedule target must be Henri");
        $test_utils:assert_eq(info["authority"], $hacker, "creator must remain Henri's verb-owner principal");
        $test_utils:assert_true(info["adaptive"], "behaviours must choose a fresh delay after each firing");
        $test_utils:assert_false(info["pass_elapsed"], "callback arguments remain explicit");
      endfor
      henri:start_behaviours();
      $test_utils:assert_eq(mapvalues(henri.scheduled_behaviours), ids, "duplicate start must preserve IDs");
      for attempt in [1..10]
        const delay = henri:_scheduled_behaviour("grooming", "_autonomous_groom", 240, 120);
        $test_utils:assert_true(delay > 240 && delay <= 360, "fresh delays stay in the retained random range");
      endfor
      henri:stop_behaviours();
      "Commit cancellation before checking the runtime schedule store.";
      suspend(0);
      for id in (ids)
        $test_utils:assert_false(schedule_valid(id), "stop must cancel every behaviour");
      endfor
      $test_utils:assert_eq(henri.scheduled_behaviours, [], "stop must leave a map for future starts");
    finally
      valid(henri) && henri:stop_behaviours();
      valid(henri) && henri:destroy();
      valid(recording_player) && recording_player:destroy();
    endtry
    return true;
  endmethod

  method test_headless_henri_actual_native_firing owner: ARCH_WIZARD
    "Henri's actual adaptive callback runs with its explicit argument contract.";
    const henri = create($henri, $hacker, 2);
    let id = 0;
    try
      henri.behaviours_disabled = false;
      id = schedule_every(henri, "_scheduled_behaviour", 0.1,
        {"grooming", "_autonomous_groom", 0.2, 0}, ['adaptive -> true, 'pass_elapsed -> false]);
      const deadline = time() + 5;
      "Commit native registration before querying runtime diagnostics.";
      suspend(0);
      let info = schedule_info(id);
      while (time() <= deadline && info["run_count"] == 0)
        "Commit registration and wait for the native callback.";
        suspend(0.1);
        info = schedule_info(id);
      endwhile
      $test_utils:assert_true(info["run_count"] > 0, "the native Henri callback must run");
      $test_utils:assert_eq(info["fault_count"], 0, "callback argument contract must not fault");
      $test_utils:assert_true(schedule_valid(id), "the adaptive recurrence must remain live");
    finally
      schedule_stop(id);
      valid(henri) && henri:destroy();
    endtry
    return true;
  endmethod

  method test_headless_native_app_controls owner: ARCH_WIZARD
    "Untrusted callers cannot start or stop housekeeping or a foreign Henri's behaviours.";
    const housekeeping = create($housekeeping, $arch_wizard, 2);
    const henri = create($henri, $hacker, 2);
    const recording_player = this:_recording_player();
    player = recording_player;
    try
      for operation in ({"housekeeping_start", "housekeeping_stop", "henri_start", "henri_stop"})
        let denied = false;
        try
          this:_native_app_call_as_player(housekeeping, henri, operation);
        except (E_PERM)
          denied = true;
        endtry
        $test_utils:assert_true(denied, operation + " must reject the foreign principal");
      endfor
    finally
      valid(housekeeping) && housekeeping:stop();
      valid(housekeeping) && housekeeping:destroy();
      valid(henri) && henri:stop_behaviours();
      valid(henri) && henri:destroy();
      valid(recording_player) && recording_player:destroy();
    endtry
    return true;
  endmethod

  method _native_app_call_as_player owner: PLAYER
    "Call only application control regression methods as the player principal.";
    caller == this && this == #90001 || raise(E_PERM);
    const {housekeeping, henri, operation} = args;
    operation == "housekeeping_start" && return housekeeping:start();
    operation == "housekeeping_stop" && return housekeeping:stop();
    operation == "henri_start" && return henri:start_behaviours();
    operation == "henri_stop" && return henri:stop_behaviours();
    raise(E_PERM);
  endmethod
  method _recording_player owner: ARCH_WIZARD
    "Create a test-only player that records current output without a network connection.";
    caller == this && this == #90001 || raise(E_PERM);
    const recipient = create($player, $arch_wizard, 2);
    add_property(recipient, "recorded_events", {}, {$arch_wizard, "r"});
    add_verb(recipient, {$arch_wizard, "rxd", "inform_current"}, {"this", "none", "this"});
    set_verb_code(recipient, "inform_current", {
      "const {event} = args;",
      "this.recorded_events = {@this.recorded_events, event};",
      "return true;"});
    return recipient;
  endmethod

  method test_headless_housekeeping_grouped_sweep owner: ARCH_WIZARD
    "Two disconnected players from one room produce two moves and one grouped announcement.";
    const housekeeping = create($housekeeping, $arch_wizard, 2);
    const room = create($room, $arch_wizard, 2);
    const home = create($room, $arch_wizard, 2);
    const first = this:_recording_player();
    const second = this:_recording_player();
    try
      add_property(room, "housekeeper", housekeeping, {$arch_wizard, "r"});
      add_property(room, "housekeeping_events", {}, {$arch_wizard, "r"});
      add_verb(room, {$arch_wizard, "rxd", "announce"}, {"this", "none", "this"});
      set_verb_code(room, "announce", {
        "const {event} = args;",
        "if (event.actor == this.housekeeper)",
        "  this.housekeeping_events = {@this.housekeeping_events, event};",
        "endif",
        "return true;"});
      housekeeping.idle_threshold = 1;
      for participant in ({first, second})
        set_player_flag(participant, 1);
        participant.home = home;
        participant.last_disconnected = time() - 10;
        add_verb(participant, {$arch_wizard, "rxd", "moveto"}, {"this", "none", "this"});
        set_verb_code(participant, "moveto", {"const {destination} = args;", "move(this, destination);", "return true;"});
        add_verb(participant, {$arch_wizard, "rxd", "tell"}, {"this", "none", "this"});
        set_verb_code(participant, "tell", {"return true;"});
        move(participant, room);
      endfor
      $test_utils:assert_eq(housekeeping:sweep(), 2, "both successful moves must remain in the accumulator");
      $test_utils:assert_eq(first.location, home, "first player must move home");
      $test_utils:assert_eq(second.location, home, "second player must move home");
      $test_utils:assert_eq(length(room.housekeeping_events), 1, "one room must receive one grouped announcement");
    finally
      for participant in ({first, second})
        valid(participant) && set_player_flag(participant, 0);
        valid(participant) && participant:destroy();
      endfor
      valid(room) && room:destroy();
      valid(home) && home:destroy();
      valid(housekeeping) && housekeeping:destroy();
    endtry
    return true;
  endmethod

endobject
