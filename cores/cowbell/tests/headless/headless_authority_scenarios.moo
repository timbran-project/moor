// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later
object HEADLESS_AUTHORITY_SCENARIOS
  name: "Headless Authority Scenarios"
  parent: ROOT
  owner: RUNTIME_WIZARD
  readable: true

  override import_export_hierarchy = {"tests", "headless"};
  override import_export_id = "headless_authority_scenarios";

  method test_hostile_root_permission_override owner: RUNTIME_WIZARD
    "Root mutation rejects an untrusted permission checker override.";
    return this:_probe_hostile_permission_override("set_description");
  endmethod

  method test_hostile_player_permission_override owner: RUNTIME_WIZARD
    "Player mutation rejects an untrusted permission checker override.";
    return this:_probe_hostile_permission_override("set_email_address");
  endmethod

  method _probe_hostile_permission_override owner: RUNTIME_WIZARD
    "Inherited wizard mutators must validate their subject independently of child helpers.";
    const {mutation} = args;
    let target = #-1;
    let victim = #-1;
    try
      target = create($player, #90101);
      victim = create($player);
      const original_description = victim.description;
      const original_email = victim.email_address;
      add_verb(target, {#90101, "rxd", "check_permissions_with_grants_as"}, {"this", "none", "this"});
      set_verb_code(target, "check_permissions_with_grants_as", {"return {" + toliteral(victim) + ", $arch_wizard, {}};"});
      add_verb(target, {#90101, "rxd", "check_permissions_as"}, {"this", "none", "this"});
      set_verb_code(target, "check_permissions_as", {"return {" + toliteral(victim) + ", $arch_wizard};"});
      let denied = false;
      try
        this:_call_as_player(target, mutation, "unauthorized mutation");
      except (E_PERM)
        denied = true;
      endtry
      $test_utils:assert_true(denied, mutation + " must ignore the hostile authorization override");
      $test_utils:assert_eq(victim.description, original_description, "Denied description mutation must preserve state");
      $test_utils:assert_eq(victim.email_address, original_email, "Denied email mutation must preserve state");
    finally
      valid(victim) && recycle(victim);
      valid(target) && recycle(target);
    endtry
    return true;
  endmethod

  method test_pronouns_use_callers_authority owner: RUNTIME_WIZARD
    "Profile mutations honor their MOO caller even when the task player is a wizard.";
    const own_pronouns = #90102.pronouns;
    const other_pronouns = #90100.pronouns;
    try
      this:_call_as_player(#90102, "set_pronouns", "she/her");
      $test_utils:assert_eq(#90102:pronouns_display(), "she/her", "Owners can update their own pronouns");
      const denied = `this:_call_as_player(#90100, "set_pronouns", "she/her") ! E_PERM => E_PERM';
      $test_utils:assert_eq(denied, E_PERM, "Task player authority must not replace the nested caller");
      $test_utils:assert_eq(#90100.pronouns, other_pronouns, "Denied updates preserve pronouns");
      const invalid = `this:_call_as_player(#90102, "set_pronouns", "unknown pronouns") ! E_INVARG => E_INVARG';
      $test_utils:assert_eq(invalid, E_INVARG, "Unknown presets remain invalid");
      $test_utils:assert_eq(#90102:pronouns_display(), "she/her", "Invalid updates preserve pronouns");
    finally
      #90102.pronouns = own_pronouns;
      #90100.pronouns = other_pronouns;
    endtry
    return true;
  endmethod

  method test_reconnect_updates_timestamp owner: RUNTIME_WIZARD
    "Reconnect records activity through the single server callback.";
    const original = #90102.last_connected;
    try
      #90102.last_connected = 0;
      #0:user_reconnected(#90102);
      $test_utils:assert_true(#90102.last_connected > 0, "Reconnect must update last_connected");
    finally
      #90102.last_connected = original;
    endtry
    return true;
  endmethod

  method test_merge_rejects_rebound_tokens owner: RUNTIME_WIZARD
    "Merge must bind each signed target to its flyweight delegate before reissuing authority.";
    let target = #-1;
    let other = #-1;
    try
      target = create($thing);
      other = create($thing);
      const key = "dGVzdHRlc3R0ZXN0dGVzdHRlc3R0ZXN0dGVzdHRlc3Q=";
      const cap = $root:issue_capability(target, {'set_description}, 0, 0, key);
      const other_cap = $root:issue_capability(other, {'set_description}, 0, 0, key);
      const rebound = toflyweight(target, flyslots(other_cap), flycontents(other_cap));
      let denied = false;
      try
        $root:merge_capability(cap, rebound, key);
      except (E_PERM)
        denied = true;
      endtry
      $test_utils:assert_true(denied, "Merge must reject a token rebound to a different delegate");
    finally
      valid(other) && recycle(other);
      valid(target) && recycle(target);
    endtry
    return true;
  endmethod

  method test_player_setup_rejects_requested_wizard_authority owner: RUNTIME_WIZARD
    "A child-owned callback must not choose wizard authority for player setup.";
    let proxy = #-1;
    let created = #-1;
    try
      proxy = create($player, #90101);
      add_verb(proxy, {#90101, "rxd", "_invoke_setup"}, {"this", "none", "this"});
      set_verb_code(proxy, "_invoke_setup", {"return this:_make_player_setup_cap($arch_wizard);"});
      let denied = false;
      try
        const cap = this:_call_as_player(proxy, "_invoke_setup", 0);
        created = cap.delegate;
      except (E_PERM)
        denied = true;
      endtry
      $test_utils:assert_true(denied, "A child callback must not request wizard setup authority");
    finally
      valid(created) && recycle(created);
      valid(proxy) && recycle(proxy);
    endtry
    return true;
  endmethod

  method _call_as_player owner: RUNTIME_PLAYER
    "Run a mutation with the ordinary fixture principal's permissions.";
    caller == #90010 || raise(E_PERM);
    const {target, mutation, value} = args;
    mutation in {"set_description", "set_email_address", "set_pronouns", "_invoke_setup"} || raise(E_PERM);
    return target:(mutation)(value);
  endmethod

  method test_walk_driver_rejects_unrelated_callers owner: RUNTIME_WIZARD
    "The fork-only walking driver must not install a victim's authority for an unrelated caller.";
    let target = #-1;
    try
      target = create($player, #90101);
      move(target, #90103);
      add_verb(target, {#90101, "rxd", "inform_current"}, {"this", "none", "this"});
      set_verb_code(target, "inform_current", {"return 0;"});
      let denied = false;
      try
        this:_call_walk_as_player(target);
      except (E_PERM)
        denied = true;
      endtry
      $test_utils:assert_true(denied, "The internal walk driver must reject an unrelated caller");
    finally
      valid(target) && recycle(target);
    endtry
    return true;
  endmethod

  method _call_walk_as_player owner: RUNTIME_PLAYER
    "Attempt to invoke the internal walking driver as an ordinary principal.";
    caller == #90010 || raise(E_PERM);
    const {target} = args;
    return target:_do_walk({{target.location, 0}});
  endmethod
  method test_login_setup_requires_wizard owner: RUNTIME_WIZARD
    "Ordinary callers must not create a welcome mailbox for a wizard-owned player.";
    const original_letter = $login.new_player_letter;
    const original_contents = $mail_room.contents;
    let target = #-1;
    try
      target = create($player, #90100);
      $login.new_player_letter = {#90100, "authority welcome", {"probe"}};
      let denied = false;
      try
        this:_call_login_setup_as_player(target);
      except (E_PERM)
        denied = true;
      endtry
      $test_utils:assert_true(denied, "An ordinary caller must not allocate another player's welcome mailbox");
      $test_utils:assert_eq($mail_room.contents, original_contents, "Denied setup must not allocate a mailbox");
      $login:setup_new_player(target);
      $test_utils:assert_eq(length($mail_room.contents), length(original_contents) + 1, "Wizard setup must create one mailbox");
    finally
      $login.new_player_letter = original_letter;
      for mailbox in ($mail_room.contents)
        if (!(mailbox in original_contents))
          for letter in (mailbox.contents)
            recycle(letter);
          endfor
          recycle(mailbox);
        endif
      endfor
      valid(target) && recycle(target);
    endtry
    return true;
  endmethod

  method _call_login_setup_as_player owner: RUNTIME_PLAYER
    "Invoke login setup under the ordinary fixture principal.";
    caller == #90010 || raise(E_PERM);
    const {target} = args;
    return $login:setup_new_player(target);
  endmethod
endobject
