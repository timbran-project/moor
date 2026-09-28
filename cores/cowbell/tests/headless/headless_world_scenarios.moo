// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later
object HEADLESS_WORLD_SCENARIOS
  name: "World Boundary Scenarios"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true
  override import_export_id = "headless_world_scenarios";
  override import_export_hierarchy = {"tests", "headless"};
  method test_foreign_area_cleanup_denied owner: ARCH_WIZARD
    "Only authorized lifecycle code may remove another area's passages.";
    const area = create($area, $arch_wizard, 2);
    const room_a = create($room, $arch_wizard, 2);
    const room_b = create($room, $arch_wizard, 2);
    try
      const passage = <$passage, .side_a_room = room_a, .side_b_room = room_b, .is_open = true>;
      area:set_passage(room_a, room_b, passage);
      $test_utils:assert_eq(length(area:passages()), 1, "fixture has a real passage");
      try
        this:_as_programmer("area_cleanup", area, room_a);
      except (E_PERM)
      endtry
      $test_utils:assert_eq(length(area:passages()), 1, "foreign cleanup must preserve the passage");
    finally
      recycle(room_a);
      recycle(room_b);
      area:destroy();
    endtry
    return true;
  endmethod

  method test_passage_foreign_movement_denied owner: ARCH_WIZARD
    "Public passage construction does not authorize moving another owner's object.";
    const room_a = create($room, $arch_wizard, 2);
    const room_b = create($room, $arch_wizard, 2);
    const victim = create($thing, $arch_wizard, 2);
    try
      move(victim, room_a);
      try
        this:_as_programmer("passage_move", victim, room_a, room_b);
      except (E_PERM)
      endtry
      $test_utils:assert_eq(victim.location, room_a, "foreign passage traversal must not move the victim");
    finally
      recycle(victim);
      recycle(room_a);
      recycle(room_b);
    endtry
    return true;
  endmethod

  method _as_programmer owner: RUNTIME_PROGRAMMER
    "Run the public operation as a verified nonwizard programmer.";
    caller == this && this == #90014 || raise(E_PERM);
    const {operation, subject, @rest} = args;
    if (operation == "reaction")
      return $reaction:execute_effect({'set, 'audit_value, 7}, ['Actor -> #90101, 'This -> subject], subject);
    elseif (operation == "area_cleanup")
      return subject:on_room_recycle(rest[1]);
    elseif (operation == "passage_move")
      const {from_room, to_room} = rest;
      const passage = $passage:mk(from_room, "east", {}, "", true, to_room, "west", {}, "", true);
      return passage:travel_from(subject, from_room, []);
    endif
    raise(E_INVARG);
  endmethod
  method test_owner_area_and_room_lifecycle owner: ARCH_WIZARD
    "Nonwizard owners can initialize an area and recycle an owned room in a foreign area.";
    const owned_area = create($area, #90101, 2);
    const foreign_area = create($area, #90100, 2);
    const room_a = create($room, #90101, 2);
    const room_b = create($room, #90100, 2);
    try
      const passage = <$passage, .side_a_room = room_a, .side_b_room = room_b, .is_open = true>;
      this:call_as_programmer(owned_area, "set_passage", room_a, room_b, passage);
      $test_utils:assert_eq(length(owned_area:passages()), 1, "owner can register passage");
      this:call_as_programmer(owned_area, "on_room_recycle", room_a);
      $test_utils:assert_eq(length(owned_area:passages()), 0, "owner cleanup succeeds");
      foreign_area:set_passage(room_a, room_b, passage);
      move(room_a, foreign_area);
      this:call_as_programmer(room_a, "destroy");
      $test_utils:assert_eq(length(foreign_area:passages()), 0, "actual room recycle cleans foreign area's member link");
    finally
      valid(room_a) && recycle(room_a);
      recycle(room_b);
      owned_area:destroy();
      foreign_area:destroy();
    endtry
  endmethod

  method call_as_programmer owner: RUNTIME_PROGRAMMER
    "Invoke a world entry with verified nonwizard permissions.";
    const {target, method, @parameters} = args;
    return target:(method)(@parameters);
  endmethod

  method test_container_rejects_supplied_foreign_actor owner: ARCH_WIZARD
    "A programmer cannot select the owner's identity to open a restricted container.";
    const container = create($container, #90100, 2);
    const prior_location = #90100.location;
    move(#90100, #-1);
    try
      container.open = false;
      container.open_rule = $rule_engine:parse_expression("This owner_is(Accessor)?", 'owner_open);
      const result = `this:call_as_programmer(container, "action_open", #90100, []) ! E_PERM => E_PERM';
      $test_utils:assert_eq(result, E_PERM, "supplied foreign actor denied");
      $test_utils:assert_eq(container.open, false, "denial preserves closed state");
    finally
      move(#90100, prior_location);
      recycle(container);
    endtry
  endmethod

  method test_container_put_rechecks_custody_after_policy_yield owner: ARCH_WIZARD
    "A suspended policy callback cannot authorize moving an item that its actor no longer holds.";
    const container = create($container, #90100, 2);
    const item = create($thing, #90101, 2);
    const prior_location = #90101.location;
    move(#90101, #-1);
    try
      move(item, #90101);
      add_verb(container, {#90100, "rxd", "can_put_into"}, {"this", "none", "this"});
      set_verb_code(container, "can_put_into", {"const {who, item} = args; move(item, #90103); suspend(0); return ['allowed -> true, 'reason -> {}];"});
      const result = this:call_as_programmer(container, "action_put_into", #90101, [], item);
      $test_utils:assert_eq(result, false, "stale custody denies put");
      $test_utils:assert_eq(item.location, #90103, "callback transfer remains in its chosen location");
    finally
      move(#90101, prior_location);
      recycle(item);
      recycle(container);
    endtry
  endmethod

  method test_container_public_actions_and_restricted_denial owner: ARCH_WIZARD
    "Default public open and held-item actions succeed while configured denial preserves state.";
    const container = create($container, #90100, 2);
    const item = create($thing, #90101, 2);
    const prior_location = #90101.location;
    move(#90101, #-1);
    try
      move(item, #90101);
      $test_utils:assert_eq(this:call_as_programmer(container, "action_close", #90101, []), true, "public close succeeds");
      $test_utils:assert_eq(container.open, false, "close applied");
      $test_utils:assert_eq(this:call_as_programmer(container, "action_open", #90101, []), true, "public open succeeds");
      $test_utils:assert_eq(this:call_as_programmer(container, "action_put_into", #90101, [], item), true, "held put succeeds");
      $test_utils:assert_eq(item.location, container, "item deposited");
      $test_utils:assert_eq(this:call_as_programmer(container, "action_take_from", #90101, [], item), true, "public take succeeds");
      $test_utils:assert_eq(item.location, #90101, "item received");
      container.open = false;
      container.open_rule = $rule_engine:parse_expression("This owner_is(Accessor)?", 'owner_open);
      $test_utils:assert_eq(this:call_as_programmer(container, "action_open", #90101, []), false, "restricted actor denied");
      $test_utils:assert_eq(container.open, false, "restricted denial preserves state");
    finally
      move(#90101, prior_location);
      recycle(item);
      recycle(container);
    endtry
  endmethod

  method test_foreign_area_destroy_preserves_relation owner: ARCH_WIZARD
    "Check area recycle authority before touching its child relation.";
    const area = create($area, #90100, 2);
    const relation = area.passages_rel;
    try
      const denied = `this:call_as_programmer(area, "destroy") ! E_PERM => E_PERM';
      $test_utils:assert_eq(denied, E_PERM, "foreign area destroy denied");
      $test_utils:assert_true(valid(area) && valid(relation), "both area and child relation survive denial");
    finally
      if (valid(area))
        area:destroy();
      elseif (valid(relation))
        relation:destroy();
      endif
    endtry
  endmethod

  method test_passage_failed_accept_preserves_actor_location owner: ARCH_WIZARD
    "A real destination rejection propagates without moving the authorized traveler.";
    const from_room = create($room, #90100, 2);
    const to_room = create($room, #90100, 2);
    const traveler = create($thing, #90101, 2);
    try
      move(traveler, from_room);
      add_verb(to_room, {#90100, "rxd", "accept"}, {"this", "none", "this"});
      set_verb_code(to_room, "accept", {"return false;"});
      const rejected = `this:_as_programmer("passage_move", traveler, from_room, to_room) ! E_NACC => E_NACC';
      $test_utils:assert_eq(rejected, E_NACC, "native destination rejection preserved");
      $test_utils:assert_eq(traveler.location, from_room, "rejection preserves actor location");
    finally
      recycle(traveler);
      recycle(from_room);
      recycle(to_room);
    endtry
  endmethod

  method test_passage_helpers_reject_hostile_self_call owner: ARCH_WIZARD
    "An ordinary child cannot choose a wizard principal for inherited relation helpers.";
    const area = create($area, #90101, 2);
    const room_a = create($room, #90100, 2);
    const room_b = create($room, #90100, 2);
    try
      add_verb(area, {#90101, "rxd", "attack_passage"}, {"this", "none", "this"});
      set_verb_code(area, "attack_passage", {"const {a, b} = args; return this:_do_create_passage(a, b, <$passage, .side_a_room = a, .side_b_room = b>, $arch_wizard);"});
      const denied = `area:attack_passage(room_a, room_b) ! E_PERM => E_PERM';
      $test_utils:assert_eq(denied, E_PERM, "self-call cannot supply a wizard principal");
      $test_utils:assert_eq(length(area:passages()), 0, "denied helper preserves empty relation");
    finally
      recycle(room_a);
      recycle(room_b);
      area:destroy();
    endtry
  endmethod

  method test_passage_authorization_overrides_cannot_grant owner: ARCH_WIZARD
    "A foreign area's permission override cannot authorize raw passage creation.";
    const area = create($area, #90100, 2);
    const room_a = create($room, #90100, 2);
    const room_b = create($room, #90100, 2);
    try
      add_verb(area, {#90101, "rxd", "check_permissions_as"}, {"this", "none", "this"});
      set_verb_code(area, "check_permissions_as", {"return {this, $arch_wizard};"});
      const passage = <$passage, .side_a_room = room_a, .side_b_room = room_b, .side_b_label = "", .side_b_aliases = {}>;
      const denied = `this:call_as_programmer(area, "create_passage", room_a, room_b, passage) ! E_PERM => E_PERM';
      $test_utils:assert_eq(denied, E_PERM, "foreign override cannot forge authority");
      $test_utils:assert_eq(length(area:passages()), 0, "denied creation preserves relation");
    finally
      recycle(room_a);
      recycle(room_b);
      area:destroy();
    endtry
  endmethod

  method test_passage_update_ignores_fake_existing_link owner: ARCH_WIZARD
    "Source digging authority cannot create a link through an overridden lookup.";
    const area = create($area, #90100, 2);
    const room_a = create($room, #90101, 2);
    const room_b = create($room, #90100, 2);
    try
      add_verb(area, {#90101, "rxd", "passage_for"}, {"this", "none", "this"});
      set_verb_code(area, "passage_for", {"const {a, b} = args; return <$passage, .side_a_room = a, .side_b_room = b>;"});
      const replacement = <$passage, .side_a_room = room_a, .side_b_room = room_b>;
      const denied = `this:call_as_programmer(area, "update_passage", room_a, room_b, replacement) ! E_INVARG => E_INVARG';
      $test_utils:assert_eq(denied, E_INVARG, "update requires actual stored link");
      $test_utils:assert_eq(length(area:passages()), 0, "denied update cannot create a link");
    finally
      recycle(room_a);
      recycle(room_b);
      area:destroy();
    endtry
  endmethod


endobject

object #90108
  name: "Runtime World Area"
  parent: AREA
  owner: RUNTIME_WIZARD
endobject

object #90109
  name: "Runtime World West Room"
  parent: ROOM
  owner: RUNTIME_WIZARD
  location: #90108
endobject

object #90110
  name: "Runtime World East Room"
  parent: ROOM
  owner: RUNTIME_WIZARD
  location: #90108
endobject

object #90111
  name: "Runtime World Container"
  parent: CONTAINER
  owner: RUNTIME_WIZARD
  location: RUNTIME_ROOM
endobject

object #90112
  name: "Runtime World Item"
  parent: THING
  owner: RUNTIME_PLAYER
  location: RUNTIME_PLAYER
endobject
