object HEADLESS_BUILDER_COMMAND_SCENARIOS
  name: "Headless Builder Command Scenarios"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  override description = "Headless integration scenarios for builder command wrappers.";
  override import_export_id = "headless_builder_command_scenarios";
  override import_export_hierarchy = {"tests", "headless"};

  verb test_headless_builder_commands_use_stored_grants (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: builder command verbs use stored capabilities for room and passage operations.";
    player == $player || raise(E_INVARG, "This scenario must run with --test-task-player set to PLAYER.");
    test_area = #-1;
    room_a = #-1;
    room_b = #-1;
    built_room = #-1;
    old_player_location = $player.location;
    old_is_builder = $player.is_builder;
    stubbed_inform = false;
    added_inform_log = false;
    try
      test_area = create($area);
      room_a = test_area:make_room_in($room);
      room_b = test_area:make_room_in($room);
      room_a:set_name_aliases("builder source room", {"builder-source"});
      room_b:set_name_aliases("builder target room", {"builder-target"});
      $player.is_builder = true;
      add_property($player, "headless_last_inform", false, {$arch_wizard, "r"});
      added_inform_log = true;
      add_verb($player, {$arch_wizard, "rxd", "inform_current"}, {"this", "none", "this"});
      compile_errors = set_verb_code($player, "inform_current", {"this.headless_last_inform = args;", "return true;"}, 2, 1);
      $test_utils:assert_false(compile_errors, "temporary inform_current stub should compile");
      stubbed_inform = true;
      $player:moveto(room_a);
      $root:grant_capability(test_area, {'add_room, 'create_passage, 'remove_passage}, $player, 'area);
      $root:grant_capability(room_a, {'dig_from}, $player, 'room);
      $root:grant_capability(room_b, {'dig_into}, $player, 'room);
      build_result = this:_dispatch_builder_any("@build", "builder cap room in " + tostr(test_area), {});
      built_room = this:_find_room_named_in_area(test_area, "builder cap room");
      $test_utils:assert_true(valid(built_room), "@build should create a room through stored area grant");
      $test_utils:assert_eq(build_result, built_room, "@build should return the created room");
      dig_result = this:_dispatch_builder_any("@dig", "oneway north to builder target room", {"oneway north"}, "to", "builder target room");
      $test_utils:assert_type(dig_result, TYPE_FLYWEIGHT, "@dig should return the new passage: " + toliteral($player.headless_last_inform));
      $test_utils:assert_eq(test_area:passage_for(room_a, room_b), dig_result, "@dig should register passage through stored grants");
      undig_result = this:_dispatch_builder_dobj("@undig", "north");
      $test_utils:assert_true(undig_result, "@undig should report successful removal");
      $test_utils:assert_false(test_area:passage_for(room_a, room_b), "@undig should remove passage through stored grants");
    finally
      stubbed_inform && `delete_verb($player, "inform_current") ! E_VERBNF => 0';
      added_inform_log && `delete_property($player, "headless_last_inform") ! E_PROPNF => 0';
      valid(built_room) && built_room:destroy();
      $player.is_builder = old_is_builder;
      valid(old_player_location) && $player:moveto(old_player_location);
      valid(room_b) && room_b:destroy();
      valid(room_a) && room_a:destroy();
      valid(test_area) && test_area:destroy();
    endtry
    return true;
  endverb

  verb _dispatch_builder_any (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Dispatch a builder command declared as any/any/any.";
    {verb_name, arg_string, command_args, ?prep_string = "", ?iobj_string = ""} = args;
    pc = [
      'verb -> verb_name,
      'argstr -> arg_string,
      'args -> command_args,
      'dobj -> player,
      'dobjstr -> command_args ? command_args[1] | arg_string,
      'prep -> -2,
      'prepstr -> prep_string,
      'iobj -> player,
      'iobjstr -> iobj_string
    ];
    return dispatch_command_verb($builder_features, verb_name, pc);
  endverb

  verb _dispatch_builder_dobj (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Dispatch a builder command declared as any/none/none.";
    {verb_name, dobj_string} = args;
    pc = [
      'verb -> verb_name,
      'argstr -> dobj_string,
      'args -> {dobj_string},
      'dobj -> player,
      'dobjstr -> dobj_string,
      'prep -> -1,
      'prepstr -> "",
      'iobj -> #-1,
      'iobjstr -> ""
    ];
    return dispatch_command_verb($builder_features, verb_name, pc);
  endverb

  verb _find_room_named_in_area (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the first room in area with the given name.";
    {area, room_name} = args;
    for candidate in (area:contents())
      if (valid(candidate) && candidate.name == room_name)
        return candidate;
      endif
    endfor
    return #-1;
  endverb
endobject
