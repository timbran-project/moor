// Baseline behaviour tests for the Snore Core method harness.
// Each test_ method runs as a wizard task with the test task player and must
// raise (or return an error) to fail. Fixtures live in the test overlay only.
// Objdef constants are not visible inside verb bodies; use `$` names and the
// fixture properties below instead.

object TEST_HARNESS [
  import_export_id -> "test_harness"
]
  name: "Test Harness"
  parent: ROOT_CLASS
  owner: #2
  fertile: false
  readable: true

  property utility_private (owner: #2, flags: "") = "private utility probe";
  property utility_callback (owner: #2, flags: "r") = {value} => value * factor + offset with captured [{factor: 3, offset: 2}];

  property test_feature (owner: #2, flags: "rc") = TEST_COMMAND_FEATURE;
  property test_player (owner: #2, flags: "rc") = TEST_PLAYER;
  property test_programmer (owner: #2, flags: "rc") = TEST_PROGRAMMER;
  property test_room (owner: #2, flags: "rc") = TEST_ROOM;
  property test_room_two (owner: #2, flags: "rc") = TEST_ROOM_TWO;
  property test_game_player (owner: #2, flags: "rc") = TEST_GAME_PLAYER;
  property test_mailbox (owner: #2, flags: "rc") = TEST_MAILBOX;
  property test_exit_east (owner: #2, flags: "rc") = TEST_EXIT_EAST;
  property test_exit_west (owner: #2, flags: "rc") = TEST_EXIT_WEST;
  property test_container (owner: #2, flags: "rc") = TEST_CONTAINER;
  property delivery_count (owner: #2, flags: "rc") = 0;
  property tx_probe (owner: #2, flags: "r") = 0;
  property write_count (owner: #2, flags: "r") = 0;
  property write_log (owner: #2, flags: "r") = {};

  method test_feature_lifecycle owner: #2
    "Preserve installation authority, callback ordering, deduplication, and callback error handling.";
    const who = this.test_player;
    const outsider = this.test_programmer;
    const feature = this.test_feature;
    const original_features = who.features;
    const original_owner = feature.owner;
    try
      who.features = {};
      feature.hook_log = {};
      feature.feature_ok = true;
      feature.fail_hooks = false;
      outsider:editor_access(who, "add_feature", feature) == E_PERM ||
        raise(E_INVARG, "foreign feature installation allowed");
      outsider:editor_access(who, "remove_feature", feature) == E_PERM ||
        raise(E_INVARG, "foreign feature removal allowed");
      who:add_feature($nothing) == E_INVARG || raise(E_INVARG, "invalid feature accepted");
      who:add_feature("feature") == E_INVARG || raise(E_INVARG, "non-object feature accepted");
      who:add_feature(feature) || raise(E_INVARG, "feature installation failed");
      who:add_feature(feature) || raise(E_INVARG, "repeated feature installation failed");
      who.features == {feature} || raise(E_INVARG, "duplicate feature");
      feature.hook_log == {{"add", who, true}, {"add", who, true}} ||
        raise(E_INVARG, "installation callback contract");
      feature.owner = outsider;
      outsider:editor_access(who, "remove_feature", feature) ||
        raise(E_INVARG, "feature owner could not remove feature");
      !who.features || raise(E_INVARG, "feature owner removal failed");
      feature.owner = original_owner;
      feature.fail_hooks = true;
      who:add_feature(feature) || raise(E_INVARG, "callback error escaped installation");
      who:remove_feature(feature) || raise(E_INVARG, "callback error escaped removal");
      feature.hook_log[$] == {"remove", who, false} ||
        raise(E_INVARG, "removal callback ran before list update");
      feature.feature_ok = false;
      who:add_feature(feature) == E_PERM || raise(E_INVARG, "unwilling feature accepted");
      !who.features || raise(E_INVARG, "denied installation changed list");
    finally
      who.features = original_features;
      feature.owner = original_owner;
      feature.feature_ok = true;
      feature.fail_hooks = false;
      feature.hook_log = {};
    endtry
    return true;
  endmethod

  method test_feature_configuration owner: #2
    "Feature setters require control; feature_verbs lists help entries, not a command allowlist.";
    const feature = this.test_feature;
    const outsider = this.test_programmer;
    const original_verbs = feature.feature_verbs;
    try
      outsider:editor_access(feature, "set_feature_ok", false) == E_PERM ||
        raise(E_INVARG, "foreign feature eligibility change allowed");
      outsider:editor_access(feature, "set_feature_verbs", {}) == E_PERM ||
        raise(E_INVARG, "foreign feature help change allowed");
      feature:set_feature_ok(false) == false || raise(E_INVARG, "feature disable failed");
      feature:set_feature_ok(1) == true || raise(E_INVARG, "feature enable did not return a boolean");
      typeof(feature.feature_ok) == typeof(true) || raise(E_INVARG, "feature flag is not a boolean");
      feature:set_feature_verbs({}) == {} || raise(E_INVARG, "feature help list not stored");
      feature:has_feature_verb("pp", {"any"}, {"any"}, {"any"}) == "pp" ||
        raise(E_INVARG, "help list incorrectly restricted dispatch");
      feature:has_feature_verb("pp", {"none"}, {"any"}, {"any"}) == false ||
        raise(E_INVARG, "feature ignored argument specs");
    finally
      feature:set_feature_verbs(original_verbs);
      feature:set_feature_ok(true);
    endtry
    return true;
  endmethod

  method test_command_dispatch_boundaries owner: #2
    "Reject direct entry to system dispatch and another player's matching environment.";
    for operation in ({"do_command", "_command_handler", "_dispatch_command"})
      const denied = `this.test_programmer:editor_access(#0, operation) ! E_PERM => true';
      denied == true || raise(E_INVARG, "untrusted system entry: " + operation);
    endfor
    for operation in ({"match_environment", "command_environment"})
      const denied = `this.test_programmer:editor_access(this.test_player, operation, "look") ! E_PERM => true';
      denied == true || raise(E_INVARG, "foreign matching context: " + operation);
    endfor
    const providers = this.test_player:command_environment();
    providers[1] == this.test_player && providers[$] == this.test_player.location ||
      raise(E_INVARG, "command environment order");
    length(providers) == length($set_utils:union({}, providers)) ||
      raise(E_INVARG, "duplicate command providers");
    return true;
  endmethod

  method test_core_globals owner: #2
    "Assert that core globals resolve and key parents hold.";
    $object_utils:isa(this.test_player, $player) || raise(E_INVARG, "test player is not a $player");
    $object_utils:isa(this.test_room, $room) || raise(E_INVARG, "test room is not a $room");
    parent($player) == $root_class || raise(E_INVARG, "$player parent is not $root_class");
    parent($room) == $root_class || raise(E_INVARG, "$room parent is not $root_class");
    valid($mail_agent) || raise(E_INVARG, "$mail_agent does not resolve");
    valid($recycler) || raise(E_INVARG, "$recycler does not resolve");
    match(tostr($room), "^#[0-9]+$") || raise(E_INVARG, "core objects are not numbered");
    return true;
  endmethod

  method test_recycler_roundtrip owner: #2
    "Create and destroy a fresh object through the recycler interface.";
    created = $recycler:_create($thing, player);
    typeof(created) == TYPE_OBJ || raise(E_INVARG, "recycler create returned " + tostr(created));
    valid(created) || raise(E_INVARG, "created object is not valid");
    created.owner == player || raise(E_INVARG, "created object has the wrong owner");
    $recycler:_recycle(created);
    valid(created) && raise(E_INVARG, "recycled object is still valid");
    return true;
  endmethod

  method test_uuid_user_object owner: #2
    "Create a user-class object, set the player flag, and recycle it.";
    created = $recycler:_create($player_class, player);
    typeof(created) == TYPE_OBJ || raise(E_INVARG, "could not create user object: " + tostr(created));
    match(tostr(created), "^#[0-9]+$") && raise(E_INVARG, "created user object has a numbered identifier");
    set_player_flag(created, 1);
    is_player(created) || raise(E_INVARG, "player flag was not set");
    result = created:set_name("TestUUIDUser");
    created.name == "TestUUIDUser" || raise(E_INVARG, "name was not stored: name=" + tostr(created.name) + " result=" + tostr(result));    set_player_flag(created, 0);
    $recycler:_recycle(created);
    valid(created) && raise(E_INVARG, "recycled user object is still valid");
    return true;
  endmethod

  method test_movement_hooks owner: #2
    "Move a test player between fixture rooms and verify location changes.";
    who = this.test_player;
    room = this.test_room;
    other = this.test_room_two;
    who:moveto(room);
    who.location == room || raise(E_INVARG, "moveto did not move the player");
    who:moveto(other);
    who.location == other || raise(E_INVARG, "moveto did not reach the second room");
    who:moveto(room);
    who.location == room || raise(E_INVARG, "moveto did not return the player");
    return true;
  endmethod

  method test_permission_denial owner: #2
    "Recycling another owner's object with reduced permissions must fail.";
    set_task_perms(this.test_player);
    denied = false;
    try
      $recycler:_recycle(this.test_room);
    except (E_PERM)
      denied = true;
    endtry
    denied || raise(E_INVARG, "unauthorized recycle was allowed");
    return true;
  endmethod

  method test_gag_filter owner: #2
    "The gag predicate reports the current task player when gagged.";
    who = this.test_player;
    saved = who.gaglist;
    who.gaglist = {player};
    who:gag_p() || raise(E_INVARG, "gag_p did not report a gagged sender");
    who.gaglist = {};
    who:gag_p() && raise(E_INVARG, "gag_p reported a gagged sender after ungag");
    who.gaglist = saved;
    return true;
  endmethod

  method test_mail_delivery owner: #2
    "Send mail to a test player and verify local delivery state.";
    who = this.test_player;
    saved = who.messages;
    who.messages = {};
    result = $mail_agent:send_message(player, {who}, "Baseline subject", {"Baseline body"});
    typeof(result) == TYPE_LIST && result[1] == 1 || raise(E_INVARG, "send failed: " + tostr(result));
    length(who.messages) == 1 || raise(E_INVARG, "message was not delivered");
    who.messages[1][2][4] == "Baseline subject" || raise(E_INVARG, "stored subject is wrong");
    who.messages = saved;
    return true;
  endmethod

  method test_make_player_uuid owner: #2
    "Account creation through $wiz_utils:make_player produces a UUID player.";
    result = $wiz_utils:make_player("TestMakePlayer", "maketest@example.invalid");
    typeof(result) == TYPE_LIST && typeof(result[1]) == TYPE_OBJ || raise(E_INVARG, "make_player failed: " + tostr(result));
    who = result[1];
    is_player(who) || raise(E_INVARG, "created account is not a player");
    match(tostr(who), "^#[0-9]+$") && raise(E_INVARG, "created account has a numbered identifier");
    $wiz_utils:unset_player(who);
    $recycler:_recycle(who);
    return true;
  endmethod

  method test_creation_denial owner: #2
    "Creating an object owned by someone else with reduced permissions must fail.";
    set_task_perms(this.test_player);
    result = $recycler:_create($thing, player);
    typeof(result) == TYPE_ERR || raise(E_INVARG, "unauthorized creation returned " + tostr(result));
    result == E_INVARG || raise(E_INVARG, "unauthorized creation failed with " + tostr(result));
    return true;
  endmethod

  method test_pager_removed owner: #2
    "Paging and wrapping state, commands, and helpers are gone.";
    $object_utils:has_property($player, "pagelen") && raise(E_INVARG, "pagelen property remains");
    $object_utils:has_property($player, "linelen") && raise(E_INVARG, "linelen property remains");
    $object_utils:has_property($player, "linebuffer") && raise(E_INVARG, "linebuffer property remains");
    $object_utils:has_property($player, "linewrap") && raise(E_INVARG, "linewrap helper remains");
    $object_utils:has_callable_verb($player, "@more") && raise(E_INVARG, "@more remains");
    $object_utils:has_callable_verb($player, "@pagelength") && raise(E_INVARG, "@pagelength remains");
    $object_utils:has_callable_verb($player, "@wrap") && raise(E_INVARG, "@wrap remains");
    return true;
  endmethod

  method test_player_split owner: #2
    "The mail-capable game branch excludes default utilities and retains shared player services.";
    $player_class == $default_player || raise(E_INVARG, "wrong default class");
    const game = this.test_game_player;
    $object_utils:isa(game, $mail_recipient_class) || raise(E_INVARG, "game lacks mail");
    !$object_utils:isa(game, $default_player) || raise(E_INVARG, "game inherits default utilities");
    const base_features = {$pasting_feature, $stage_talk, $utility_feature};
    $default_player.features == base_features || raise(E_INVARG, "wrong default features");
    $builder.features == {@base_features, $builder_feature} || raise(E_INVARG, "wrong builder features");
    $prog.features == {@base_features, $builder_feature, $programmer_feature} || raise(E_INVARG, "wrong programmer features");
    $wiz.features == {@base_features, $builder_feature, $programmer_feature, $wizard_feature} || raise(E_INVARG, "wrong wizard features");
    for command in ({"@who", "@go", "@audit", "@rename", "@describe", "@messages", "@notedit", "@examine", "examine", "@edit", "@move-new", "@eject", "@features", "teleport", "_create", "eval_cmd_string", "mcd_2"})
      !$object_utils:has_verb(game, command) || raise(E_INVARG, "game exposes " + command);
      !$object_utils:has_verb($player, command) || raise(E_INVARG, "base exposes " + command);
    endfor
    for command in ({"page", "whisper", "@gag", "@ungag", "@mail", "@send", "news", "help", "@password", "@refuse", "@spurn"})
      $object_utils:has_verb(game, command) || raise(E_INVARG, "game lacks " + command);
    endfor
    $code_utils:help_db_search("@refuse", $code_utils:help_db_list(game))[1] == $mail_help || raise(E_INVARG, "game lacks refusal help");
    !$object_utils:has_verb($default_player, "_create") || raise(E_INVARG, "builder support leaked");
    $object_utils:has_verb($builder, "_create")[1] == $builder || raise(E_INVARG, "builder support misplaced");
    $object_utils:has_verb($prog, "eval_cmd_string")[1] == $prog || raise(E_INVARG, "programmer support misplaced");
    $object_utils:has_verb($wiz, "mcd_2")[1] == $wiz || raise(E_INVARG, "wizard support misplaced");
    return true;
  endmethod

  method test_role_assignment owner: #2
    "Promotion enters the programmer hierarchy and preserves unrelated installed features.";
    const result = $wiz_utils:make_player("TestRolePlayer", "roletest@example.invalid");
    typeof(result) == TYPE_LIST && typeof(result[1]) == TYPE_OBJ || raise(E_INVARG, "make_player failed");
    const who = result[1];
    try
      chparent(who, #112);
      who.features = {$pasting_feature};
      $wiz_utils:set_programmer(who) == true || raise(E_INVARG, "promotion failed");
      who.programmer && parent(who) == $prog || raise(E_INVARG, "promotion did not establish programmer class");
      who.features == {$pasting_feature, $builder_feature, $programmer_feature} || raise(E_INVARG, "promotion lost features");
      $wiz_utils:set_programmer(who) == E_NONE || raise(E_INVARG, "duplicate promotion changed state");
    finally
      $wiz_utils:unset_player(who);
      $recycler:_recycle(who);
    endtry
    return true;
  endmethod

  method test_role_registration owner: #2
    "Registration sets programmer authority from ancestry without granting wizard authority.";
    const branch = create($wiz);
    const who = create(branch);
    try
      who.name = "TestRoleRegistration";
      $wiz_utils:set_player(who) == 1 || raise(E_INVARG, "registration failed");
      who.programmer && !who.wizard || raise(E_INVARG, "wrong authority after registration");
      who.features == $wiz.features || raise(E_INVARG, "role defaults did not inherit");
      who.programmer = false;
      $wiz_utils:set_programmer(who) == true || raise(E_INVARG, "descendant promotion failed");
      parent(who) == branch || raise(E_INVARG, "promotion replaced a programmer descendant class");
    finally
      is_player(who) && $wiz_utils:unset_player(who);
      recycle(who);
      recycle(branch);
    endtry
    return true;
  endmethod

  method test_player_db_lookup owner: #2
    "Case-insensitive exact, alias, prefix, ambiguity, and missing lookups.";
    $player_db:find_exact("WIZARD") == #2 || raise(E_INVARG, "case-insensitive exact lookup failed");
    $player_db:find_exact("hacker") == #36 || raise(E_INVARG, "alias lookup failed");
    $player_db:find_exact("no_such_player_zzz") == $failed_match || raise(E_INVARG, "missing lookup did not fail");
    $player_db:find("wiza") == #2 || raise(E_INVARG, "unique prefix lookup failed");
    $player_db:insert("TestLookupAlpha", this.test_player);
    $player_db:insert("TestLookupBeta", this.test_programmer);
    $player_db:find("TestLookup") == $ambiguous_match || raise(E_INVARG, "ambiguous prefix did not report ambiguity");
    $player_db:find_exact("testlookupalpha") == this.test_player || raise(E_INVARG, "inserted name did not match");
    length($player_db:find_all("TestLookup")) == 2 || raise(E_INVARG, "find_all did not return both matches");
    $player_db:delete("TestLookupAlpha");
    $player_db:delete("TestLookupBeta");
    return true;
  endmethod

  method test_site_and_registration_db owner: #2
    "Map-backed site and registration databases keep their lookup contracts.";
    $site_db:add(this.test_player, "example.com");
    $site_db:find_exact("EXAMPLE.COM") == {this.test_player} || raise(E_INVARG, "site lookup failed");
    "example.com" in $site_db:find_all_keys("example") || raise(E_INVARG, "site prefix lookup failed");
    $site_db:delete("example.com");
    $site_db:delete("com");
    $registration_db:add(this.test_player, "Lookup@Example.invalid");
    entries = $registration_db:find_exact("lookup@example.invalid");
    typeof(entries) == TYPE_LIST && length(entries) == 1 && entries[1][1] == this.test_player || raise(E_INVARG, "registration lookup failed");
    "lookup@example.invalid" in $registration_db:find_all_keys("lookup@") || raise(E_INVARG, "registration prefix lookup failed");
    $registration_db:delete("lookup@example.invalid");
    return true;
  endmethod

  method test_paranoid_db owner: #2
    "Map-backed paranoid history stores, trims, erases, and removes non-paranoid entries.";
    who = this.test_player;
    saved = who.paranoid;
    who.paranoid = 1;
    $paranoid_db:erase_data(who);
    $paranoid_db:set_kept_lines(who, 3);
    for i in [1..5]
      $paranoid_db:add_data(who, {"line", i});
    endfor
    data = $paranoid_db:get_data(who);
    length(data) <= 3 || raise(E_INVARG, "kept-line trimming failed");
    data[$] == {"line", 5} || raise(E_INVARG, "newest entry missing");
    $paranoid_db:erase_data(who);
    length($paranoid_db:get_data(who)) == 0 || raise(E_INVARG, "erase failed");
    who.paranoid = saved;
    $paranoid_db:gc();
    maphaskey($paranoid_db.paranoid_data, who) && raise(E_INVARG, "gc kept a non-paranoid entry");
    return true;
  endmethod

  method test_options_map owner: #2
    "Player options are stored as maps and keep get/set behavior.";
    who = this.test_player;
    saved = who.display_options;
    who.display_options = [];
    who.display_options = $display_options:set(who.display_options, "shortprep", 1);
    typeof(who.display_options) == TYPE_MAP || raise(E_INVARG, "options are not a map");
    $display_options:get(who.display_options, "shortprep") == true || raise(E_INVARG, "flag is not boolean");
    who.display_options = $display_options:set(who.display_options, "shortprep", 0);
    maphaskey(who.display_options, "shortprep") && raise(E_INVARG, "flag off did not remove the option");
    strict = $display_options:set([], "shortprep", 1);
    max = $display_options:set(strict, "unknown_option", 1);
    max == "Unknown option:  unknown_option" || raise(E_INVARG, "unknown option not rejected");
    who.display_options = saved;
    return true;
  endmethod

  method test_option_contracts owner: #2
    "Check boolean flags, object values, aliases, and the option parser's retained syntax.";
    const display = $display_options;
    const enabled = display:set([], "shortprep", true);
    typeof(enabled) == TYPE_MAP || raise(E_INVARG, "could not set a boolean flag");
    const shown = display:show(enabled, "shortprep");
    index(shown[1], "+shortprep") == 1 || raise(E_INVARG, "boolean display lost the + prefix");
    index(shown[1], "Use short forms") || raise(E_INVARG, "boolean display lost its description");
    const disabled = display:set(enabled, "shortprep", false);
    !maphaskey(disabled, "shortprep") || raise(E_INVARG, "disabled flag remains stored");
    index(display:show(disabled, "shortprep")[1], "-shortprep") == 1 ||
      raise(E_INVARG, "disabled flag display lost the - prefix");
    display:parse({"+short"}) == {"shortprep", 1} || raise(E_INVARG, "+flag parsing changed");
    display:parse({"shortprep=0"}) == {"shortprep", 0} || raise(E_INVARG, "flag=value parsing changed");
    display:parse({"shortprep", "is", "1"}) == {"shortprep", 1} ||
      raise(E_INVARG, "flag is value parsing changed");
    display:parse({"shortprep"}) == {"shortprep"} || raise(E_INVARG, "query parsing changed");
    typeof(display:parse({"+shortprep", "extra"})) == TYPE_STR ||
      raise(E_INVARG, "flag accepted trailing input");
    display:parse({"unknown"}) == "Unknown option:  unknown" ||
      raise(E_INVARG, "unknown option diagnostic changed");
    const aliases = $edit_options:set([], "noisy_insert", false);
    aliases["quiet_insert"] == true || raise(E_INVARG, "inverse option alias failed");
    index($edit_options:show(aliases, "noisy_insert")[1], "+quiet_insert") == 1 ||
      raise(E_INVARG, "inverse option display failed");
    const rooms = $build_options:set([], "dig_room", this.test_room);
    rooms["dig_room"] == this.test_room || raise(E_INVARG, "object option was treated as false");
    const replies = $mail_options:set([], "replyto", this.test_player);
    replies["replyto"] == {this.test_player} || raise(E_INVARG, "reply recipient normalization failed");
    const order = $mail_options:parse({"rn-order", "is", "se"});
    order == {"rn_order", "send"} || raise(E_INVARG, "choice prefix parsing failed");
    const typed = $mail_options:set([], "expire", 20);
    typed["expire"] == 20 || raise(E_INVARG, "numeric option became a boolean");
    typeof($mail_options:set([], "expire", "many")) == TYPE_STR ||
      raise(E_INVARG, "numeric option accepted text");
    const permissions = $prog_options:set([], "@prop_flags", "rw");
    permissions["@prop_flags"] == "rw" || raise(E_INVARG, "property permission option failed");
    typeof($prog_options:set([], "@prop_flags", "x")) == TYPE_STR ||
      raise(E_INVARG, "property option accepted an invalid permission");
    const verb_args = $prog_options:set([], "verb_args", {"this", "on top of", "any"});
    verb_args["verb_args"] == {"this", "on", "any"} ||
      raise(E_INVARG, "verb preposition normalization failed");
    !($build_options:_name("bi_create") == "bi_create") ||
      raise(E_INVARG, "removed recycler option remains available");
    return true;
  endmethod

  method test_log_mail_storage owner: #2
    "The player-creation log stores messages in the inherited per-instance list.";
    log = $new_player_log;
    before = log:length_all_msgs();
    header = {time(), "From <logtest@example.invalid>", "To <log>", " ", "logtest", "", "body line"};
    new = log:receive_message(header);
    typeof(new) == TYPE_INT || raise(E_INVARG, "log receive_message failed: " + tostr(new));
    log:length_all_msgs() == before + 1 || raise(E_INVARG, "log length did not grow");
    msgs = log:messages_in_seq({new, new + 1});
    length(msgs) == 1 && msgs[1][1] == new && msgs[1][2] == header || raise(E_INVARG, "log message does not match");
    log:rm_message_seq({new, new + 1});
    log:expunge_rmm();
    log:length_all_msgs() == before || raise(E_INVARG, "log message not removed");
    return true;
  endmethod

  method measure_storage owner: #2
    "Measure per-instance mail and news storage at representative sizes and fan-out delivery.";
    box = this.test_mailbox;
    header = {time(), "From <measure@example.invalid>", "To <measure>", " ", "measure", "", "body"};
    box.messages = {};
    box.messages_going = {};
    t0 = ftime();
    for i in [1..500]
      box:receive_message(header);
    endfor
    fill500 = ftime() - t0;
    t0 = ftime();
    for i in [501..5000]
      box:receive_message(header);
      if (ticks_left() < 10000)
        suspend(0);
      endif
    endfor
    fill5000 = ftime() - t0;
    t0 = ftime();
    box:receive_message(header);
    append = ftime() - t0;
    t0 = ftime();
    range = box:messages_in_seq({2500, 2520});
    read = ftime() - t0;
    t0 = ftime();
    box:rm_message_seq({2500, 2501});
    box:expunge_rmm();
    remove = ftime() - t0;
    saved = {};
    targets = {box, this.test_player, $news, $new_player_log, $quota_log};
    for r in (targets)
      saved = {@saved, {r, r.messages, r.messages_going}};
    endfor
    t0 = ftime();
    sent = $mail_agent:send_message(player, targets, "Measure fanout", {"Fanout body"});
    fanout = ftime() - t0;
    for entry in (saved)
      {r, msgs, going} = entry;
      r.messages = msgs;
      r.messages_going = going;
    endfor
    news = $news;
    newsbase = length(news.messages);
    t0 = ftime();
    for i in [1..200]
      news:receive_message(header);
    endfor
    newsfill = ftime() - t0;
    t0 = ftime();
    newsread = length(news:messages_in_seq({newsbase + 1, newsbase + 201}));
    newsreadtime = ftime() - t0;
    news.messages = news.messages[1..newsbase];
    box.messages = {};
    summary = tostr("MEASURE mail fill500=", fill500, "s fill4500=", fill5000, "s append@5001=", append, "s read20@5001=", read, "s rmm@5001=", remove, "s fanout5=", fanout, "s news200=", newsfill, "s newsread200=", newsreadtime, "s");
    server_log(summary);
    length(range) == 20 || raise(E_INVARG, "range read returned the wrong count");
    typeof(sent) == TYPE_LIST && sent[1] == 1 || raise(E_INVARG, "fan-out send failed: " + toliteral(sent));
    newsread == 200 || raise(E_INVARG, "news range read returned the wrong count");
    spellwords = {"apple", "zebra", "database", "xylophone", "marmalade"};
    t0 = ftime();
    for word in (spellwords)
      $spell:valid(word);
    endfor
    spellvalid = ftime() - t0;
    t0 = ftime();
    spellprefix = length($spell:find_all("app"));
    spellfindall = ftime() - t0;
    spellsummary = tostr("MEASURE spell valid5=", spellvalid, "s find_all(app)=", spellfindall, "s matches=", spellprefix);
    server_log(spellsummary);
    spellprefix > 0 || raise(E_INVARG, "spell prefix lookup returned nothing");
    return true;
  endmethod

  method test_editor_state owner: #2
    "Check setters against lambda-moor core_help: save clears changes and origin stores the return room.";
    const editor = $recycler:_create($note_editor);
    editor.active = {this.test_programmer};
    editor.texts = {{"one", "two"}};
    editor.inserting = {3};
    editor.changes = {true};
    editor.readable = {false};
    editor.original = {this.test_room};
    editor.times = {123};
    const cleared = editor:set_changed(1, false);
    const changed_after_save = editor:changed(1);
    const origin = editor:set_origin(1, this.test_room_two);
    const stored_origin = editor:origin(1);
    editor:set_readable(1, true);
    const published_text = editor:text(1);
    const failure = {cleared, changed_after_save, origin, stored_origin, published_text};
    const expected = {false, false, this.test_room_two, this.test_room_two, {"one", "two"}};
    failure == expected || raise(E_INVARG, "editor state: " + toliteral(failure));
    editor.times[1] == 123 || raise(E_INVARG, "clearing changes altered the modification time");
    editor:set_changed(1, true) == true || raise(E_INVARG, "could not mark changes");
    editor.times[1] > 123 || raise(E_INVARG, "change timestamp was not updated");
    editor:set_insertion(1, 37) == 3 || raise(E_INVARG, "insertion did not clamp");
    editor:set_insertion(1, 0) == E_INVARG || raise(E_INVARG, "invalid insertion accepted");
    editor:set_origin(1, editor) == E_INVARG || raise(E_INVARG, "editor accepted itself as origin");
    editor:set_origin(1, $nothing) == $nothing || raise(E_INVARG, "nothing origin rejected");
    editor:origin(1) == $nothing || raise(E_INVARG, "nothing origin not stored");
    editor:load(1, "replacement");
    editor:text(1) == {"replacement"} || raise(E_INVARG, "load text mismatch");
    editor:insertion(1) == 2 || raise(E_INVARG, "load did not reset insertion");
    !editor:changed(1) && !editor:readable(1) ||
      raise(E_INVARG, "load did not reset flags");
    typeof(editor:changed(1)) == TYPE_BOOL && typeof(editor:readable(1)) == TYPE_BOOL ||
      raise(E_INVARG, "load did not store boolean flags");
    editor:load(1, 42) == E_TYPE || raise(E_INVARG, "nontext load accepted");
    editor:text(1) == {"replacement"} || raise(E_INVARG, "failed load changed buffer");
    $recycler:_recycle(editor);
    return true;
  endmethod

  method test_editor_session_identity owner: #2
    "Buffer replacement invalidates input identity; index shifts and ordinary edits do not.";
    const editor = $recycler:_create($generic_editor);
    add_verb(editor, {player, "rxd", "new_probe"}, {"this", "none", "this"});
    set_verb_code(editor, "new_probe", {"return this:new_session(@args);"});
    editor:new_probe(this.test_player, this.test_room) == 1 || raise(E_INVARG, "first session");
    editor:new_probe(this.test_programmer, this.test_room) == 2 || raise(E_INVARG, "second session");
    editor:load(1, {"first"});
    editor:load(2, {"second"});
    const original = editor.input_versions[this.test_programmer];
    editor:load(2, {"second"});
    const replaced = editor.input_versions[this.test_programmer];
    replaced != original || raise(E_INVARG, "identical reload retained identity");
    editor:set_insertion(2, 1);
    editor:insert_line(2, "edit", true);
    editor:new_probe(this.test_programmer, this.test_room_two) == -1 ||
      raise(E_INVARG, "reentry replaced session");
    editor.input_versions[this.test_programmer] == replaced ||
      raise(E_INVARG, "ordinary editing changed identity");
    editor:reset_session(2);
    !editor:loaded(this.test_programmer) || raise(E_INVARG, "reset kept buffer");
    editor.input_versions[this.test_programmer] != replaced || raise(E_INVARG, "reset kept identity");
    editor:load(2, {"restored"});
    const retained = editor.input_versions[this.test_programmer];
    editor:kill_session(1);
    editor:loaded(this.test_programmer) == 1 || raise(E_INVARG, "session index did not shift");
    editor.input_versions[this.test_programmer] == retained || raise(E_INVARG, "shift changed identity");
    !maphaskey(editor.input_versions, this.test_player) || raise(E_INVARG, "removed identity retained");
    editor:kill_session(1);
    editor:new_probe(this.test_programmer, this.test_room) == 1 || raise(E_INVARG, "recreate session");
    editor.input_versions[this.test_programmer] != retained || raise(E_INVARG, "recreated identity reused");
    this.test_programmer:editor_access(editor, "_renew_input_version", 1) == E_PERM ||
      raise(E_INVARG, "external identity mutation allowed");
    this.test_programmer:editor_access(editor, "_read_into_buffer") == E_PERM ||
      raise(E_INVARG, "external input entry allowed");
    editor:kill_all_sessions();
    editor.input_versions == [] || raise(E_INVARG, "flush retained input identities");
    $recycler:_recycle(editor);
    return true;
  endmethod

  method test_editor_access owner: #2
    "Keep private editor buffers and setters inaccessible through another player's methods.";
    const editor = $recycler:_create($note_editor);
    editor.active = {this.test_player};
    editor.texts = {{"private text"}};
    editor.inserting = {2};
    editor.changes = {true};
    editor.readable = {false};
    editor.original = {this.test_room};
    editor.times = {123};
    const outsider = this.test_programmer;
    outsider:editor_access(editor, "readable", 1) == false ||
      raise(E_INVARG, "editor access fixture cannot read the public flag");
    for operation in ({"insertion", "changed", "origin", "text"})
      outsider:editor_access(editor, operation, 1) == E_PERM ||
        raise(E_INVARG, "private getter allowed: " + operation);
    endfor
    for entry in ({{"set_insertion", 1}, {"set_changed", false},
                   {"set_origin", this.test_room_two}, {"set_readable", true},
                   {"load", {"intrusion"}}})
      outsider:editor_access(editor, entry[1], 1, entry[2]) == E_PERM ||
        raise(E_INVARG, "private setter allowed: " + entry[1]);
    endfor
    editor:text(1) == {"private text"} && editor:changed(1) && !editor:readable(1) ||
      raise(E_INVARG, "denied operation changed state");
    for operation in ({"insertion", "changed", "origin", "text", "readable"})
      editor:(operation)(0) == E_RANGE || raise(E_INVARG, "invalid session accepted: " + operation);
    endfor
    editor:set_readable(1, true);
    outsider:editor_access(editor, "text", 1) == {"private text"} ||
      raise(E_INVARG, "published buffer did not return text");
    outsider:editor_access(editor, "set_changed", 1, false) == E_PERM ||
      raise(E_INVARG, "publishing granted write access");
    $recycler:_recycle(editor);
    return true;
  endmethod

  method test_published_mail_preview owner: #2
    "Publishing mail must preserve the message returned to the mail editor's print command.";
    const editor = $recycler:_create($mail_editor);
    editor.active = {this.test_player};
    editor.texts = {{"preview body"}};
    editor.readable = {false};
    editor.recipients = {{this.test_player}};
    editor.subjects = {"preview subject"};
    editor.replytos = {{}};
    const private_message = editor:message_with_headers(1);
    typeof(private_message) == TYPE_LIST || raise(E_INVARG, "private preview is not a message");
    this.test_programmer:editor_access(editor, "message_with_headers", 1) == E_PERM ||
      raise(E_INVARG, "private mail preview accessible to another player");
    editor:set_readable(1, true);
    const published_message = this.test_programmer:editor_access(editor, "message_with_headers", 1);
    typeof(published_message) == TYPE_LIST ||
      raise(E_INVARG, "published mail preview returned " + toliteral(published_message));
    published_message[2..$] == private_message[2..$] ||
      raise(E_INVARG, "publishing altered preview content");
    $recycler:_recycle(editor);
    return true;
  endmethod

  method test_editor_buffers owner: #2
    "Exercise buffer edits, cursor movement, change flags, and no-text errors.";
    const editor = $recycler:_create($note_editor);
    const saved_options = player.edit_options;
    player.edit_options = ["quiet_insert" -> true];
    editor.active = {player};
    editor.texts = {{}};
    editor.inserting = {1};
    editor.changes = {false};
    editor.readable = {false};
    editor.times = {0};
    editor:load(1, {"first", "last"});
    editor:set_insertion(1, 2);
    editor:insert_line(1, {"middle", "next"}, true);
    editor:text(1) == {"first", "middle", "next", "last"} || raise(E_INVARG, "insert order");
    editor:insertion(1) == 4 && editor:changed(1) || raise(E_INVARG, "insert cursor and flag");
    editor:append_line(1, "!");
    editor:text(1)[3] == "next!" || raise(E_INVARG, "append target");
    editor:insertion(1) == 4 || raise(E_INVARG, "append moved cursor");
    editor:set_insertion(1, 1);
    editor:append_line(1, "new first");
    editor:text(1)[1..2] == {"new first", "first"} || raise(E_INVARG, "append at start");
    editor:insertion(1) == 2 || raise(E_INVARG, "start insertion cursor");
    editor:load(1, {"left", "right", "tail"});
    editor:set_insertion(1, 2);
    editor:join_lines(1, 1, 2, false) == 1 || raise(E_INVARG, "join removed count");
    editor:text(1) == {"leftright", "tail"} || raise(E_INVARG, "literal join");
    editor:insertion(1) == 2 && editor:changed(1) || raise(E_INVARG, "joined cursor and flag");
    editor:load(1, {"Sentence.", "words", "  ", "tail"});
    editor:join_lines(1, 1, 3, true) == 2 || raise(E_INVARG, "sentence join removed count");
    editor:text(1) == {"Sentence.  words ", "tail"} || raise(E_INVARG, "sentence spacing");
    editor:insertion(1) == 3 || raise(E_INVARG, "cursor after joined range");
    editor:join_lines(1, 1, 1, false) == 0 || raise(E_INVARG, "single-line join");
    editor.texts[1] = 0;
    editor:loaded(player) == 0 || raise(E_INVARG, "unloaded session reported loaded");
    editor:insert_line(1, "text", true) == E_NONE || raise(E_INVARG, "insert into unloaded text");
    editor:append_line(1, "text") == E_NONE || raise(E_INVARG, "append into unloaded text");
    player.edit_options = saved_options;
    $recycler:_recycle(editor);
    return true;
  endmethod

  method test_editor_regexp_replacement owner: #2
    "Replace original matches once, with captures, boundaries, empty matches, and Unicode positions.";
    const cases = {
      {{"a", "a", "a", true, true}, "a"},
      {{"a", "a", "aa", true, true}, "aa"},
      {{"aaa", "a", "aa", true, true}, "aaaaaa"},
      {{"aaa", "a", "", true, true}, ""},
      {{"aba", "a", "X", true}, "Xba"},
      {{"aba", "a", "X", true, true}, "XbX"},
      {{"ab", "^", "X", true, true}, "Xab"},
      {{"ab", "$", "X", true, true}, "abX"},
      {{"", "^$", "X", true, true}, "X"},
      {{"aa aa", "%<", ">", true, true}, ">aa >aa"},
      {{"ab", "", "-", true, true}, "-a-b-"},
      {{"aba", "%(a%)", "%1!", true, true}, "a!ba!"},
      {{"ab ab", "%(a%)%(b%)", "%2-%1", true, true}, "b-a b-a"},
      {{"aA", "a", "x", true, true}, "xA"},
      {{"aA", "a", "x", false, true}, "xx"},
      {{"é🙂", ".", "X", true, true}, "XX"},
      {{"abc", "z", "X", true, true}, {}}
    };
    for entry in (cases)
      const result = $generic_editor:subst_regexp(@entry[1]);
      const expected = entry[2];
      const correct = typeof(expected) == TYPE_STR
        ? typeof(result) == TYPE_STR && strcmp(result, expected) == 0
        | result == expected;
      correct || raise(E_INVARG, "editor regex replacement: " + toliteral({entry[1], result}));
    endfor
    return true;
  endmethod

  method test_editor_positions owner: #2
    "Check the line and insertion syntax documented in lambda-moor's editor help.";
    const editor = $recycler:_create($note_editor);
    editor.active = {player};
    editor.texts = {{"one", "two", "three", "four", "five"}};
    editor.inserting = {3};
    const line_cases = {{"1", 1}, {"_", 2}, {"^", 3}, {"$", 5}, {"2_", 1},
                       {"2^", 4}, {"2$", 4}, {"", 0}, {"bad", 0}};
    for entry in (line_cases)
      editor:parse_number(1, entry[1], false) == entry[2] ||
        raise(E_INVARG, "wrong editor line: " + entry[1]);
    endfor
    const dot_lines = {`editor:parse_number(1, ".", false) ! ANY',
                       `editor:parse_number(1, ".", true) ! ANY'};
    const insertion_cases = {{"1", 1}, {"^2", 2}, {"_2", 3}, {"$", 6}, {"^$", 5},
                            {"2^$", 4}, {".", 3}, {"+2", 5}, {"-2", 1}, {"+0", 3},
                            {"-0", 3}, {"", E_INVARG}, {"bad", E_INVARG}, {"+bad", E_INVARG}};
    let insertions = {};
    let expected = {};
    for entry in (insertion_cases)
      insertions = {@insertions, `editor:parse_insert(1, entry[1]) ! ANY'};
      expected = {@expected, entry[2]};
    endfor
    $recycler:_recycle(editor);
    dot_lines == {3, 2} && insertions == expected ||
      raise(E_INVARG, "editor positions: dot=" + toliteral(dot_lines) + "; insert=" + toliteral(insertions));
    return true;
  endmethod

  method test_editor_ranges owner: #2
    "Check range defaults, unconsumed words, and substitution syntax without changing editor state.";
    const editor = $recycler:_create($note_editor);
    editor.active = {player};
    editor.texts = {{"one", "two", "three", "four", "five"}};
    editor.inserting = {3};
    const defaults = {"1-$"};
    editor:parse_range(1, defaults) == {1, 5, ""} || raise(E_INVARG, "default range");
    editor:parse_range(1, {"8_-8^", "1-$"}) == {1, 5, ""} || raise(E_INVARG, "fallback range");
    editor:parse_range(1, defaults, "2-4", "nonum") == {2, 4, "nonum"} || raise(E_INVARG, "hyphen range");
    editor:parse_range(1, defaults, "2", "4", "nonum") == {2, 4, "nonum"} || raise(E_INVARG, "pair range");
    editor:parse_range(1, defaults, "2", "nonum") == {2, 2, "nonum"} || raise(E_INVARG, "single line");
    editor:parse_range(1, defaults, "nonum") == {1, 5, "nonum"} || raise(E_INVARG, "default with suffix");
    editor:parse_range(1, defaults, "from", "2", "to", "4", "nonum") == {2, 4, "nonum"} || raise(E_INVARG, "named range");
    editor:parse_range(1, defaults, "to", "3") == {1, 3, ""} || raise(E_INVARG, "to-only range");
    editor:parse_range(1, defaults, "from", "3") == {3, 5, ""} || raise(E_INVARG, "from-only range");
    editor:parse_range(1, defaults, "from") == "from ?" || raise(E_INVARG, "missing from");
    editor:parse_range(1, defaults, "to", "bad") == "to ?" || raise(E_INVARG, "invalid to");
    editor:parse_range(1, defaults, "4-2") == "from 4 to 2?  (backwards range)" || raise(E_INVARG, "backward range");
    editor:parse_range(1, defaults, "0-2") == "from 0?  (out of range)" || raise(E_INVARG, "low bound");
    editor:parse_range(1, defaults, "2-6") == "to 6?  (out of range)" || raise(E_INVARG, "high bound");
    editor:parse_subst("/one/two/gc2-4") == {"one", "two", "gc", "2-4"} || raise(E_INVARG, "substitution flags");
    editor:parse_subst("#one#two") == {"one", "two", "", ""} || raise(E_INVARG, "alternate delimiter");
    editor:parse_subst("/one//r$") == {"one", "", "r", "$"} || raise(E_INVARG, "deletion substitution");
    editor:parse_subst("///", "gcr", "empty") == "empty" || raise(E_INVARG, "empty substitution");
    editor:parse_insert(0, ".") == E_RANGE || raise(E_INVARG, "invalid editor session");
    editor.texts = {{}};
    editor:parse_range(1, defaults) == editor:no_text_msg() || raise(E_INVARG, "empty editor text");
    $recycler:_recycle(editor);
    return true;
  endmethod

  method measure_interaction owner: #2
    "Measure retained interaction workloads: chat, lookup, create/recycle, and long output.";
    speaker = this.test_player;
    room = this.test_room;
    listener = this.test_programmer;
    saved_speaker = speaker.location;
    saved_listener = listener.location;
    speaker:moveto(room);
    listener:moveto(room);
    t0 = ftime();
    for i in [1..200]
      room:announce_all(speaker.name, " says, \"measure line ", i, "\"");
    endfor
    chat = ftime() - t0;
    t0 = ftime();
    for i in [1..500]
      $player_db:find_exact("wizard");
    endfor
    lookup = ftime() - t0;
    t0 = ftime();
    made = {};
    for i in [1..50]
      made = {@made, $recycler:_create($thing)};
    endfor
    created = ftime() - t0;
    t0 = ftime();
    for thing in (made)
      $recycler:_recycle(thing);
    endfor
    recycled = ftime() - t0;
    lines = {};
    for i in [1..2000]
      lines = {@lines, "long output line " + tostr(i)};
    endfor
    t0 = ftime();
    player:tell_lines(lines);
    output = ftime() - t0;
    ed = $recycler:_create($note_editor);
    ed.active = {player};
    ed.texts = {{}};
    ed.inserting = {1};
    ed.changes = {0};
    ed.readable = {0};
    ed.times = {0};
    ed:load(1, lines);
    t0 = ftime();
    for i in [1..200]
      ed:insert_line(1, "editor line");
    endfor
    editor = ftime() - t0;
    $recycler:_recycle(ed);
    speaker:moveto(saved_speaker);
    listener:moveto(saved_listener);
    summary = tostr("MEASURE interactions chat200=", chat, "s lookup500=", lookup, "s create50=", created, "s recycle50=", recycled, "s output2000=", output, "s editor200=", editor, "s");
    server_log(summary);
    return true;
  endmethod

  method test_mail_order_and_perms owner: #2
    "Message numbers stay monotonic and direct writes require recipient permission.";
    box = this.test_mailbox;
    saved = box.messages;
    box.messages = {};
    box.messages_going = {};
    first = box:receive_message({time(), "From <a@example.invalid>", "To <box>", " ", "one", "", "body"});
    second = box:receive_message({time(), "From <a@example.invalid>", "To <box>", " ", "two", "", "body"});
    second == first + 1 || raise(E_INVARG, "message numbers are not monotonic");
    box.messages[1][2][5] == "one" && box.messages[2][2][5] == "two" || raise(E_INVARG, "message order changed");
    box:ok_write(this, this.test_player) && raise(E_INVARG, "non-writer passed the mail write check");
    box:is_writable_by(this.test_player) && raise(E_INVARG, "non-writer is listed as able to write mail");
    $news:ok_write(this, this.test_player) && raise(E_INVARG, "non-writer passed the news write check");
    $news:is_writable_by(this.test_player) && raise(E_INVARG, "non-writer is listed as able to write news");
    box.messages = saved;
    return true;
  endmethod

  method test_spell_map owner: #2
    "Spell dictionary is one map with working lookups and edits.";
    $spell:valid("apple") || raise(E_INVARG, "known word rejected");
    $spell:valid("zzzqqqxyz") && raise(E_INVARG, "unknown word accepted");
    $spell:find_exact("APPLE") == "apple" || raise(E_INVARG, "find_exact did not return the dictionary spelling");
    $spell:find_exact("zzzqqqxyz") == $failed_match || raise(E_INVARG, "missing word not reported failed");
    "apple" in $spell:find_all("appl") || raise(E_INVARG, "prefix lookup missed apple");
    typeof($spell.words) == TYPE_LIST || raise(E_INVARG, "words is not a list");
    length($spell.words) == $spell.entries || raise(E_INVARG, "entries does not match the word list");
    before = $spell.entries;
    $spell:add_word("zzmoorishxx") || raise(E_INVARG, "add_word did not report a new word");
    $spell.entries == before + 1 || raise(E_INVARG, "entries did not grow");
    $spell:add_word("zzmoorishxx") && raise(E_INVARG, "add_word accepted a duplicate");
    $spell:valid("zzmoorishxx") || raise(E_INVARG, "added word not found");
    $spell:remove_word("zzmoorishxx") || raise(E_INVARG, "remove_word did not report removal");
    $spell.entries == before || raise(E_INVARG, "entries did not return");
    $spell:valid("zzmoorishxx") && raise(E_INVARG, "removed word still found");
    return true;
  endmethod

  method test_mail_multiple_recipients owner: #2
    "One message delivered to multiple recipients leaves an independent copy for each.";
    a = this.test_player;
    b = this.test_programmer;
    saved_a = a.messages;
    saved_b = b.messages;
    a.messages = {};
    b.messages = {};
    result = $mail_agent:send_message(player, {a, b}, "Multi subject", {"Multi body"});
    typeof(result) == TYPE_LIST && result[1] == 1 || raise(E_INVARG, "multi-recipient send failed: " + toliteral(result));
    length(a.messages) == 1 && length(b.messages) == 1 || raise(E_INVARG, "one recipient missed the message");
    a.messages[1][2][4] == "Multi subject" && b.messages[1][2][4] == "Multi subject" || raise(E_INVARG, "stored subject is wrong");
    a.messages = saved_a;
    b.messages = saved_b;
    return true;
  endmethod

  method test_mail_sequence_parsing owner: #2
    "Message sequence parsing handles numbers, ranges, and relative forms.";
    who = this.test_player;
    saved = who.messages;
    who.messages = {{1, {"From <a>", "to", "date", "one", "", "body"}}, {2, {"From <a>", "to", "date", "two", "", "body"}}, {3, {"From <a>", "to", "date", "three", "", "body"}}};
    who:parse_message_seq({"2"}, 0) == {{2, 3}} || raise(E_INVARG, "single number parse failed");
    who:parse_message_seq({"1-3"}, 0) == {{1, 4}} || raise(E_INVARG, "range parse failed");
    who:parse_message_seq({"next-3"}, 1) == {{2, 4}} || raise(E_INVARG, "next range parse failed");
    who:parse_message_seq({"prev-2"}, 3) == {{2, 3}} || raise(E_INVARG, "prev range parse failed");
    who:parse_message_seq({"last"}, 0) == {{3, 4}} || raise(E_INVARG, "last parse failed");
    who.messages = saved;
    return true;
  endmethod

  method test_concurrent_delivery owner: #2
    "Two background deliveries to the same mailbox both land.";
    who = this.test_player;
    saved = who.messages;
    saved_count = this.delivery_count;
    who.messages = {};
    this.delivery_count = 0;
    fork (0)
      $mail_agent:send_message(player, {who}, "concurrent one", {"body"});
      this.delivery_count = this.delivery_count + 1;
    endfork
    fork (0)
      $mail_agent:send_message(player, {who}, "concurrent two", {"body"});
      this.delivery_count = this.delivery_count + 1;
    endfork
    deadline = time() + 10;
    while (this.delivery_count < 2 && time() < deadline)
      suspend(0);
    endwhile
    count = this.delivery_count;
    subjects = {message[2][4] for message in (who.messages)};
    who.messages = saved;
    this.delivery_count = saved_count;
    count == 2 || raise(E_INVARG, "deliveries did not complete: " + tostr(count));
    length(subjects) == 2 && "concurrent one" in subjects && "concurrent two" in subjects || raise(E_INVARG, "concurrent deliveries did not both land: " + toliteral(subjects));
    return true;
  endmethod

  method test_login_matching owner: #2
    "Login name matching accepts the default guest, literal objects, and reports misses.";
    valid($player_db:find_exact("guest")) || raise(E_INVARG, "default guest is not registered");
    $login:_match_player("guest") == $default_guest || raise(E_INVARG, "guest alias did not match");
    $login:_match_player(tostr(this.test_player)) == this.test_player || raise(E_INVARG, "literal object did not match");
    $login:_match_player("zz-no-such-player") == $failed_match || raise(E_INVARG, "missing player did not fail");
    return true;
  endmethod

  method test_authoring_denials owner: #2
    "Editing another player's object is denied; inherited members remain usable.";
    who = this.test_player;
    result = who:attempt_foreign_edit(this.test_programmer);
    result == E_PERM || raise(E_INVARG, "foreign edit was not denied: " + toliteral(result));
    saved = who.description;
    who:set_description({"inherited property write"});
    who.description == {"inherited property write"} || raise(E_INVARG, "owner cannot write an inherited property");
    who.description = saved;
    typeof(who:title()) == TYPE_STR || raise(E_INVARG, "inherited verb call failed");
    return true;
  endmethod

  method test_movement_denial owner: #2
    "A locked destination refuses entry and leaves the player in place.";
    who = this.test_player;
    exit = this.test_exit_east;
    target = this.test_room_two;
    who:moveto(this.test_room);
    target.free_entry = 0;
    exit:move(who);
    who.location == this.test_room || raise(E_INVARG, "denied move changed the location");
    target.free_entry = 1;
    exit:move(who);
    who.location == target || raise(E_INVARG, "allowed move did not arrive");
    who:moveto(this.test_room);
    return true;
  endmethod

  method test_world_broadcast owner: #2
    "Exit broadcasts preserve exclusion lists for scalar and multiline messages.";
    const room = create($room);
    const exit = create($exit);
    let listeners = {};
    try
      for index in [1..3]
        const listener = create($thing);
        listeners = {@listeners, listener};
        add_property(listener, "received", {}, {player, "rc"});
        add_verb(listener, {player, "rxd", "tell tell_lines"}, {"this", "none", "this"});
        set_verb_code(listener, "tell", {"this.received = {@this.received, tostr(@args)};"});
        move(listener, room);
      endfor
      const {excluded, broken, recipient} = listeners;
      set_verb_code(broken, "tell", {"raise(E_INVARG, \"deliberately broken listener\");"});
      exit:announce_all_but(room, {excluded}, "one");
      excluded.received == {} || raise(E_INVARG, "excluded listener received scalar message");
      recipient.received == {"one"} || raise(E_INVARG, "scalar broadcast did not reach recipient");
      exit:announce_all_but(room, {excluded}, "prefix: ", {"two", "three"});
      recipient.received == {"one", "prefix: two", "three"} || raise(E_INVARG, "multiline broadcast changed content");
      excluded.received == {} || raise(E_INVARG, "excluded listener received multiline message");
      exit:announce_all_but(room, {excluded}, {});
      recipient.received == {"one", "prefix: two", "three"} || raise(E_INVARG, "empty broadcast emitted output");
    finally
      for listener in (listeners)
        recycle(listener);
      endfor
      recycle(exit);
      recycle(room);
    endtry
    return true;
  endmethod

  method test_container_visibility owner: #2
    "Opacity keeps integer modes while opened and dark use booleans; denied setters leave state unchanged.";
    const box = create($container);
    try
      for opened in ({false, true})
        box:set_opened(opened) == opened || raise(E_INVARG, "opening setter changed boolean contract");
        for opacity in ({-1, 0, 1, 2, 3})
          const clamped = min(2, max(0, opacity));
          box:set_opaque(opacity) == clamped || raise(E_INVARG, "wrong opacity clamp");
          box.dark == (clamped > (opened ? 1 | 0)) || raise(E_INVARG, "wrong visibility");
          box.opened == opened || raise(E_INVARG, "opacity changed opening state");
        endfor
      endfor
      const state = {box.opened, box.opaque, box.dark};
      box:set_opaque("opaque") == E_INVARG || raise(E_INVARG, "non-integer opacity accepted");
      this.test_programmer:editor_access(box, "set_opened", false) == E_PERM || raise(E_INVARG, "foreign opening setter allowed");
      this.test_programmer:editor_access(box, "set_opaque", 0) == E_PERM || raise(E_INVARG, "foreign opacity setter allowed");
      {box.opened, box.opaque, box.dark} == state || raise(E_INVARG, "denied setter changed state");
    finally
      recycle(box);
    endtry
    return true;
  endmethod

  method test_exit_registration_authority owner: #2
    "Room registration writes require authority; an exit and its source owner retain their hooks.";
    const source = create($room);
    const destination = create($room);
    const exit = create($exit);
    const outsider = this.test_programmer;
    try
      exit.source = source;
      exit.dest = destination;
      source:add_exit(exit) == true || raise(E_INVARG, "exit registration failed");
      destination:add_entrance(exit) == true || raise(E_INVARG, "entrance registration failed");
      outsider:editor_access(source, "remove_exit", exit) == false || raise(E_INVARG, "foreign exit removal allowed");
      outsider:editor_access(destination, "remove_entrance", exit) == false || raise(E_INVARG, "foreign entrance removal allowed");
      outsider:editor_access(exit, "set_name", "forbidden") == E_PERM || raise(E_INVARG, "foreign rename allowed");
      source.owner = outsider;
      outsider:editor_access(exit, "set_name", "north") == true || raise(E_INVARG, "source owner rename denied");
      outsider:editor_access(exit, "set_aliases", {"n", "north"}) == true || raise(E_INVARG, "source owner aliases denied");
      source:match_exit("N") == exit || raise(E_INVARG, "exit alias matching changed");
      exit:recycle();
      source.exits == {} && destination.entrances == {} || raise(E_INVARG, "exit cleanup left registrations");
    finally
      recycle(exit);
      recycle(destination);
      recycle(source);
    endtry
    return true;
  endmethod

  method test_container_locking owner: #2
    "Container open state and keyed opening.";
    box = this.test_container;
    holder = this.test_player;
    other = this.test_programmer;
    box.opened = 0;
    box.open_key = 0;
    box:is_openable_by(holder) || raise(E_INVARG, "unlocked container refused opening");
    key = $lock_utils:parse_keyexp(tostr(holder), holder);
    $lock_utils:eval_key(key, holder) || raise(E_INVARG, "key did not match its holder");
    $lock_utils:eval_key(key, other) && raise(E_INVARG, "key matched another player");
    box.open_key = key;
    box:is_openable_by(holder) || raise(E_INVARG, "key holder refused opening");
    box:is_openable_by(other) && raise(E_INVARG, "non-key holder allowed opening");
    composite = $lock_utils:parse_keyexp(tostr(holder) + "|" + tostr(other), holder);
    $lock_utils:eval_key(composite, other) || raise(E_INVARG, "alternative key did not match");
    negated = $lock_utils:parse_keyexp("!" + tostr(other), holder);
    $lock_utils:eval_key(negated, other) && raise(E_INVARG, "negated key matched its subject");
    $lock_utils:eval_key(negated, holder) || raise(E_INVARG, "negated key rejected a non-subject");
    box:set_opened(1);
    box.opened || raise(E_INVARG, "set_opened did not open the container");
    box:set_opened(0);
    box.opened && raise(E_INVARG, "set_opened did not close the container");
    box.open_key = 0;
    box.opened = 0;
    return true;
  endmethod

  method test_verb_compile_errors owner: #2
    "A malformed program reports errors and leaves the previous code in place.";
    thing = $recycler:_create($thing);
    thing.name = "CompileProbe";
    add_verb(thing, {player, "rxd", "greet"}, {"this", "none", "this"});
    set_verb_code(thing, "greet", {"return \"hello\";"});
    errors = set_verb_code(thing, "greet", {"return \"unterminated"});
    length(errors) > 0 || raise(E_INVARG, "malformed program was accepted");
    verb_code(thing, "greet") == {"return \"hello\";"} || raise(E_INVARG, "failed compile changed the code");
    $recycler:_recycle(thing);
    return true;
  endmethod

  method test_player_administration owner: #2
    "Create, promote, toad, and recycle a runtime player.";
    created = $wiz_utils:make_player("AdminProbe", "admin@example.invalid");
    new = created[1];
    is_player(new) || raise(E_INVARG, "created character is not a player");
    new.programmer && raise(E_INVARG, "new character should not start as programmer");
    $quota_utils:get_quota(new) == 20000 || raise(E_INVARG, "default quota not applied");
    $wiz_utils:set_programmer(new);
    new.programmer || raise(E_INVARG, "promotion did not set the programmer flag");
    new.wizard && raise(E_INVARG, "promotion granted wizard");
    result = $wiz_utils:unset_player(new);
    typeof(result) == TYPE_ERR && raise(E_INVARG, "toading failed: " + toliteral(result));
    is_player(new) && raise(E_INVARG, "toaded character still has the player flag");
    $player_db:find_exact("AdminProbe") == $failed_match || raise(E_INVARG, "toaded name still resolves");
    $recycler:_recycle(new);
    $recycler:valid(new) && raise(E_INVARG, "toaded character was not recycled");
    return true;
  endmethod
  method test_mail_sequence_ops owner: #2
    "Removal undo, renumber, keep marks, and body annotation on a folder.";
    who = this.test_player;
    saved = who.messages;
    saved_going = who.messages_going;
    saved_kept = who.messages_kept;
    who.messages_going = {};
    who.messages_kept = {};
    who.messages = {{1, {"From <a@example.invalid>", "to", "date", "one", "", "body one"}}, {2, {"From <b@example.invalid>", "to", "date", "two", "", "body two"}}, {3, {"From <a@example.invalid>", "to", "date", "three", "", "body three"}}};
    removed = who:rm_message_seq({2, 3});
    removed == "2" || raise(E_INVARG, "rmm returned " + toliteral(removed));
    length(who.messages) == 2 || raise(E_INVARG, "rmm did not remove the message");
    who:undo_rmm();
    length(who.messages) == 3 || raise(E_INVARG, "undo did not restore the message");
    who:rm_message_seq({2, 3});
    who:expunge_rmm();
    result = who:renumber();
    result[1] == 2 || raise(E_INVARG, "renumber returned " + toliteral(result));
    who.messages[1][1] == 1 && who.messages[2][1] == 2 || raise(E_INVARG, "renumber left gaps");
    who:keep_message_seq({2, 3});
    who:kept_msg_seq({1, 3}) == {2, 3} || raise(E_INVARG, "keep mark not recorded: " + toliteral(who:kept_msg_seq({1, 3})));
    who:keep_message_seq({});
    length(who.messages_kept) == 0 || raise(E_INVARG, "keep clear failed");
    who.messages = saved;
    who.messages_going = saved_going;
    who.messages_kept = saved_kept;
    box = this.test_mailbox;
    saved_box = box.messages;
    saved_box_going = box.messages_going;
    saved_box_kept = box.messages_kept;
    box.messages_going = {};
    box.messages_kept = {};
    box.messages = {{1, {"From <a@example.invalid>", "to", "date", "one", "", "body one"}}, {2, {"From <b@example.invalid>", "to", "date", "two", "", "body two"}}};
    box:annotate_message_seq({"annotation"}, "append", {2, 3});
    "annotation" in box:message_body_by_index(2) || raise(E_INVARG, "annotation missing from the body");
    box.messages = saved_box;
    box.messages_going = saved_box_going;
    box.messages_kept = saved_box_kept;
    return true;
  endmethod

  method test_competing_writes owner: #2
    "Two forks that reread then write one property must both land.";
    "The read and the write happen in the same transaction after resumption; a value cached before a";
    "suspension is stale and must be reread.";
    saved = this.write_count;
    this.write_count = 0;
    fork (0)
      suspend(0);
      this.write_count = this.write_count + 1;
    endfork
    fork (0)
      suspend(0);
      this.write_count = this.write_count + 1;
    endfork
    deadline = time() + 10;
    while (this.write_count < 2 && time() < deadline)
      suspend(0);
    endwhile
    result = this.write_count;
    this.write_count = saved;
    result == 2 || raise(E_INVARG, "a concurrent update was lost: " + tostr(result));
    return true;
  endmethod

  method test_concurrent_name_change owner: #2
    "Two concurrent registrations for one player must both survive.";
    who = this.test_player;
    name_a = "ConcurrentNameA";
    name_b = "ConcurrentNameB";
    $player_db:delete2(name_a, who);
    $player_db:delete2(name_b, who);
    fork (0)
      $player_db:insert(name_a, who);
    endfork
    fork (0)
      $player_db:insert(name_b, who);
    endfork
    deadline = time() + 10;
    while ((!$player_db:find_exact(name_a) || !$player_db:find_exact(name_b)) && time() < deadline)
      suspend(0);
    endwhile
    found_a = $player_db:find_exact(name_a);
    found_b = $player_db:find_exact(name_b);
    $player_db:delete2(name_a, who);
    $player_db:delete2(name_b, who);
    found_a == who || raise(E_INVARG, "first concurrent name was lost: " + tostr(found_a));
    found_b == who || raise(E_INVARG, "second concurrent name was lost: " + tostr(found_b));
    return true;
  endmethod
  method test_initialize_owned_uuid owner: #2
    "Ownership repair rebuilds missing UUID entries and removes stale and foreign entries.";
    const who = this.test_programmer;
    const item = create($thing, who);
    const foreign = create($thing, this.test_player);
    const stale = create($thing, who);
    const uuid_owner = create($player, who);
    uuid_owner.owner = uuid_owner;
    const uuid_owned = create($thing, uuid_owner);
    $recycler:_recycle(stale);
    try
      who.owned_objects = {foreign, stale, #-1};
      uuid_owner.owned_objects = {};
      who:editor_access($wiz_utils, "initialize_owned") == E_PERM ||
        raise(E_INVARG, "non-wizard ownership repair allowed");
      who.owned_objects == {foreign, stale, #-1} ||
        raise(E_INVARG, "denied repair changed ownership records");
      $wiz_utils:initialize_owned();
      item in who.owned_objects || raise(E_INVARG, "repair missed a UUID object");
      who.owned_objects == owned_objects(who) ||
        raise(E_INVARG, "repaired ownership differs from database ownership");
      foreign in this.test_player.owned_objects ||
        raise(E_INVARG, "repair missed the foreign object's real owner");
      !is_player(uuid_owner) || raise(E_INVARG, "fixture unexpectedly has the player flag");
      uuid_owner.owned_objects == owned_objects(uuid_owner) ||
        raise(E_INVARG, "repair missed a UUID owner without the player flag");
      $wiz_utils:initialize_owned();
      who.owned_objects == owned_objects(who) || raise(E_INVARG, "repair is not idempotent");
    finally
      $recycler:_recycle(item);
      $recycler:_recycle(foreign);
      $recycler:_recycle(uuid_owned);
      $recycler:_recycle(uuid_owner);
    endtry
    return true;
  endmethod

  method test_recycle_hook_preserves_ownership owner: #2
    "A direct recycle hook call must not hide a live UUID object from ownership accounting.";
    const who = this.test_programmer;
    $quota_utils:initialize_quota(who);
    who.owned_objects = who.owned_objects;
    const item = who:editor_access($recycler, "_create", $thing);
    typeof(item) == TYPE_OBJ || raise(E_INVARG, "fixture creation failed");
    const before = who.size_quota;
    try
      item in who.owned_objects || raise(E_INVARG, "creation omitted ownership entry");
      who:editor_access(item, "recycle");
      valid(item) || raise(E_INVARG, "hook deleted the object");
      item in who.owned_objects || raise(E_INVARG, "hook hid a live object from ownership accounting");
      who.size_quota == before || raise(E_INVARG, "hook changed quota for a live object");
      who:editor_access(this.test_room, "recycle") == E_PERM ||
        raise(E_INVARG, "foreign recycle hook was allowed");
      who:editor_access($building_utils, "recreate", item, $note) ||
        raise(E_INVARG, "recreate failed");
      parent(item) == $note || raise(E_INVARG, "recreate did not change parent");
      item in who.owned_objects || raise(E_INVARG, "recreate omitted ownership entry");
      who:editor_access($recycler, "_recycle", item);
      !valid(item) || raise(E_INVARG, "recycling left object alive");
      !(item in who.owned_objects) || raise(E_INVARG, "recycling left ownership entry");
    finally
      valid(item) && $recycler:_recycle(item);
    endtry
    return true;
  endmethod

  method test_recycle_nonplayer_owner owner: #2
    "Keep explicit ownership lists correct for owners outside the player hierarchy.";
    const owner = $recycler:_create($thing);
    add_property(owner, "owned_objects", {}, {owner, "r"});
    const item = create($thing, owner);
    try
      item in owner.owned_objects || raise(E_INVARG, "creation omitted ownership entry");
      item:recycle();
      item in owner.owned_objects || raise(E_INVARG, "hook hid a live object");
      $recycler:_recycle(item);
      !valid(item) || raise(E_INVARG, "recycling left object alive");
      owner.owned_objects == {} || raise(E_INVARG, "non-player owner retained deleted object");
    finally
      valid(item) && $recycler:_recycle(item);
      $recycler:_recycle(owner);
    endtry
    return true;
  endmethod

  method test_recycler_quota_property_checks owner: #2
    "Byte quota checks reject inherited quota and ownership state without a repair task.";
    const who = this.test_programmer;
    $quota_utils:initialize_quota(who);
    const saved_quota = who.size_quota;
    const saved_owned = who.owned_objects;
    try
      who.owned_objects = saved_owned;
      who:editor_access($recycler, "check_quota_scam", who);
      clear_property(who, "owned_objects");
      `who:editor_access($recycler, "check_quota_scam", who) ! E_QUOTA' == E_QUOTA ||
        raise(E_INVARG, "inherited ownership list accepted");
      who.owned_objects = saved_owned;
      clear_property(who, "size_quota");
      `who:editor_access($recycler, "check_quota_scam", who) ! E_QUOTA' == E_QUOTA ||
        raise(E_INVARG, "inherited quota accepted");
    finally
      who.size_quota = saved_quota;
      who.owned_objects = saved_owned;
    endtry
    return true;
  endmethod

  method test_recycle_refunds_quota owner: #2
    "Repeated UUID creation and recycling restores quota and ownership records.";
    const who = this.test_player;
    $quota_utils:initialize_quota(who);
    who.owned_objects = {};
    const before = who.size_quota;
    set_task_perms(who);
    for iteration in [1..5]
      const item = $recycler:_create($thing);
      typeof(item) == TYPE_OBJ || raise(E_INVARG, "creation failed before quota was exhausted");
      $recycler:_recycle(item);
      valid(item) && raise(E_INVARG, "recycled object remains valid");
    endfor
    return this:assert_recycle_quota(who, before);
  endmethod

  method assert_recycle_quota owner: #2
    "Check private quota bookkeeping for the lifecycle regression.";
    const {who, before} = args;
    who.size_quota == before || raise(E_INVARG, "recycling leaked quota");
    who.owned_objects == {} || raise(E_INVARG, "recycling left an ownership entry");
    return true;
  endmethod
  method test_player_paranoid_frames owner: #2
    "Single-line and multiline anti-spoofing preserve caller frames for later inspection.";
    const who = this.test_player;
    const saved_mode = who.paranoid;
    const saved_gag = who.gaglist;
    const saved_data = $paranoid_db.paranoid_data;
    try
      who.gaglist = {};
      who.paranoid = 1;
      $paranoid_db:erase_data(who);
      who:tell("record one");
      who:tell_lines({"record two", "record three"});
      const records = $paranoid_db:get_data(who);
      length(records) == 2 || raise(E_INVARG, "missing anti-spoof records");
      for record in (records)
        for frame in (record[1])
          typeof(frame) == TYPE_LIST || raise(E_INVARG, "flattened caller frame");
          length(frame) >= 3 || raise(E_INVARG, "incomplete caller frame");
        endfor
        who:whodunnit(record[1], {who, $no_one}, {});
      endfor
      who.paranoid = 2;
      who:tell_lines({"immediate one", "immediate two"});
    finally
      who.paranoid = saved_mode;
      who.gaglist = saved_gag;
      $paranoid_db.paranoid_data = saved_data;
    endtry
  endmethod

  method test_player_at_output owner: #2
    "Location listings keep one complete line per room regardless of client width.";
    const who = this.test_player;
    const numbered = who.at_number;
    try
      who.at_number = true;
      const party = {who, this.test_programmer, this.test_game_player};
      const output = who:at_item(this.test_room, party);
      typeof(output) == TYPE_LIST && length(output) == 1 ||
        raise(E_INVARG, "location listing wrapped output");
      for member in (party)
        index(output[1], member.name) || raise(E_INVARG, "location listing lost a player");
      endfor
      index(output[1], tostr(this.test_room)) || raise(E_INVARG, "missing room identifier");
      index(who:at_item($nothing, {}), "[deserted]") ||
        raise(E_INVARG, "empty location display changed");
    finally
      who.at_number = numbered;
    endtry
  endmethod

  method test_player_setting_authority owner: #2
    "Player settings retain owner checks, home acceptance, and the additive brief counter.";
    const who = this.test_player;
    const outsider = this.test_programmer;
    const room = this.test_room_two;
    const saved_home = who.home;
    const saved_brief = who.brief;
    const saved_free = room.free_home;
    try
      outsider:editor_access(who, "set_brief", 3) == E_PERM || raise(E_INVARG, "foreign brief update");
      outsider:editor_access(who, "set_home", room) == E_PERM || raise(E_INVARG, "foreign home update");
      outsider:editor_access(who, "set_aliases", {"foreign"}) == E_PERM || raise(E_INVARG, "foreign aliases");
      outsider:editor_access(who, "set_name", "ForeignName") == E_PERM || raise(E_INVARG, "foreign name");
      who:set_brief(2);
      who:set_brief(3, true);
      who.brief == 5 || raise(E_INVARG, "brief counter became a flag");
      room.free_home = false;
      who:set_home(room) == E_INVARG || raise(E_INVARG, "unwilling home accepted");
      who.home == saved_home || raise(E_INVARG, "failed home change wrote state");
      room.free_home = true;
      who:set_home(room) || raise(E_INVARG, "willing home rejected");
      who.home == room || raise(E_INVARG, "home not stored");
      who:moveto($nothing) == E_INVARG || raise(E_INVARG, "player moved into void");
    finally
      who.home = saved_home;
      who.brief = saved_brief;
      room.free_home = saved_free;
    endtry
  endmethod

  method test_collection_lists owner: #2
    "Check retained mapping, association, sorting, nesting, and returned-error contracts.";
    $list_utils:make(0) == {} && $list_utils:make(5, 7) == {7, 7, 7, 7, 7} || raise(E_INVARG);
    $list_utils:make(-1) == E_INVARG || raise(E_INVARG);
    $list_utils:range(3) == {1, 2, 3} && $list_utils:range(3, 2) == {} || raise(E_INVARG);
    $list_utils:map_args($string_utils, "uppercase", {"a", "b"}) == {"A", "B"} || raise(E_INVARG);
    $list_utils:map_args(2, $list_utils, "count", 1, {{1, 1}, {2}}) == {2, 0} || raise(E_INVARG);
    $list_utils:map_verb({$string_utils, $string_utils}, "uppercase", "abc") == {"ABC", "ABC"} || raise(E_INVARG);
    $list_utils:map_prop({$list_utils, $set_utils}, "name") == {$list_utils.name, $set_utils.name} || raise(E_INVARG);
    $list_utils:map_builtin({1, 2}, "tostr") == {"1", "2"} || raise(E_INVARG);
    $list_utils:map_builtin({}, "not_a_builtin") == E_INVARG || raise(E_INVARG);
    const rows = {7, {}, {1, "first"}, {2, "second"}, {1, "later"}};
    $list_utils:assoc(1, rows) == {1, "first"} && $list_utils:iassoc(1, rows) == 3 || raise(E_INVARG);
    $list_utils:assoc_suspended(2, rows) == {2, "second"} || raise(E_INVARG);
    $list_utils:iassoc_suspended(9, rows) == 0 || raise(E_INVARG);
    $list_utils:iassoc_new(1, {{}}) == E_RANGE || raise(E_INVARG);
    const words = {{"Beta", 1}, {"beta", 2}, {"Alpha", 3}};
    $list_utils:sort_alist(words) == {{"Alpha", 3}, {"Beta", 1}, {"beta", 2}} || raise(E_INVARG);
    $list_utils:sort_alist_suspended(0, words) == $list_utils:sort_alist(words) || raise(E_INVARG);
    $list_utils:sort_suspended(0, {"c", "a", "b"}, {3, 1, 2}) == {"a", "b", "c"} || raise(E_INVARG);
    const many = {{index % 3, index} for index in [1..90]};
    const expected = {@{row for row in (many) if row[1] == 0}, @{row_one for row_one in (many) if row_one[1] == 1}, @{row_two for row_two in (many) if row_two[1] == 2}};
    $list_utils:sort_alist(many) == expected || raise(E_INVARG, "large stable sort");
    $list_utils:find_insert({1, 2, 2, 4}, 2) == 4 && $list_utils:iassoc_sorted(2, {{1}, {2}, {2}, {4}}) == 3 || raise(E_INVARG);
    $list_utils:slice(words, {2, 1}) == {{1, "Beta"}, {2, "beta"}, {3, "Alpha"}} || raise(E_INVARG);
    $list_utils:assoc_prefix("be", words) == {"Beta", 1} && $list_utils:iassoc_prefix("al", words) == 3 || raise(E_INVARG);
    $list_utils:amerge({{"a", 1}, {"b", 2}, {"a", 3}}, 1, 2) == {{1, "a", 3}, {2, "b"}} || raise(E_INVARG);
    $list_utils:arrayset({{1, 2}, {3, 4}}, 9, 2, 1) == {{1, 2}, {9, 4}} || raise(E_INVARG);
    $list_utils:append({1}, {}, {2, 3}) == {1, 2, 3} || raise(E_INVARG);
    $list_utils:flatten({1, {2, {}, {3}}, 4}) == {1, 2, 3, 4} || raise(E_INVARG);
    $list_utils:flatten_suspended({1, {2, {}, {3}}, 4}) == {1, 2, 3, 4} || raise(E_INVARG);
    $list_utils:remove_duplicates({"A", "a", 1, 1}) == {"A", 1} || raise(E_INVARG);
    $list_utils:compress({1, 1, 2, 1, 1}) == {1, 2, 1} || raise(E_INVARG);
    $list_utils:setremove_all({1, 2, 1, 3}, 1) == {2, 3} || raise(E_INVARG);
    $list_utils:count(1, {1, 2, 1}) == 2 && $list_utils:count(1, 2) == E_INVARG || raise(E_INVARG);
    $list_utils:longest({"ab", {1, 2}, "c"}) == "ab" && $list_utils:shortest({"ab", "c", "d"}) == "c" || raise(E_INVARG);
    $list_utils:longest({}) == E_RANGE && $list_utils:shortest({1}) == E_TYPE || raise(E_INVARG);
    $list_utils:swap_elements({1, 2, 3}, 1, 3) == {3, 2, 1} || raise(E_INVARG);
    $list_utils:setmove({1, 2, 3}, 1, 3) == {2, 3, 1} || raise(E_INVARG);
    $list_utils:passoc("a", {"a", "b"}, {7, 8}) == 7 || raise(E_INVARG);
    $list_utils:build_alist({1, 2, 3, 4}, 2) == {{1, 2}, {3, 4}} || raise(E_INVARG);
    $list_utils:build_alist({1}, 0) == E_INVARG && $list_utils:build_alist({1}, 2) == E_RANGE || raise(E_INVARG);
    const input = {1, 1, 2, 3, 4};
    sort($list_utils:randomly_permute(input)) == input || raise(E_INVARG);
    sort($list_utils:randomly_permute_suspended(input)) == input || raise(E_INVARG);
    $list_utils:reverse(input) == {4, 3, 2, 1, 1} && $list_utils:reverse_suspended(input) == {4, 3, 2, 1, 1} || raise(E_INVARG);
    $list_utils:random_item({}) == E_RANGE && $list_utils:random_item({7}) == 7 || raise(E_INVARG);
    return true;
  endmethod
  method test_collection_sets owner: #2
    "Check all set operations, boolean predicates, case representatives, and exactly-once xor semantics.";
    $set_utils:union() == {} && $set_utils:intersection() == {} || raise(E_INVARG);
    $set_utils:union({"A", 1}, {"a", 2}) == {"A", 1, 2} || raise(E_INVARG);
    const common = $set_utils:intersection({"A", 1, 2}, {"a", 2});
    strcmp(common[1], "a") == 0 && common[2] == 2 || raise(E_INVARG);
    const preserved = $set_utils:intersection_preserve_case({"A", 1, 2}, {"a", 2});
    strcmp(preserved[1], "A") == 0 && preserved[2] == 2 || raise(E_INVARG);
    $set_utils:difference({1, 2, 3}, {2}, {3}) == {1} || raise(E_INVARG);
    $set_utils:difference_suspended({1, 2, 3}, {2}, {3}) == {1} || raise(E_INVARG);
    $set_utils:exclusive_or({1, 2}, {1, 3}, {1, 4}) == {2, 3, 4} || raise(E_INVARG);
    $set_utils:contains({1, 2}, {2}) && !$set_utils:contains({1}, {2}) || raise(E_INVARG);
    $set_utils:equal({1, 1, "a"}, {"A", 1}) && !$set_utils:equal({1}, {1, 2}) || raise(E_INVARG);
    typeof($set_utils:contains()) == TYPE_BOOL && typeof($set_utils:equal({}, {})) == TYPE_BOOL || raise(E_INVARG);
    return true;
  endmethod
  method test_collection_sequence_sets owner: #2
    "Compare sequence algebra with finite set membership over all pairs of four-bit sets.";
    const weights = {1, 2, 4, 8};
    let all_sequences = {};
    for mask in [0..15]
      const items = {position_1 for position_1 in [1..4] if mask / weights[position_1] % 2};
      all_sequences = {@all_sequences, $seq_utils:from_list(items)};
    endfor
    for left_mask in [0..15]
      const left = all_sequences[left_mask + 1];
      const left_values = {position_2 for position_2 in [1..4] if left_mask / weights[position_2] % 2};
      $seq_utils:tolist(left) == left_values || raise(E_INVARG, "conversion");
      for right_mask in [0..15]
        const right = all_sequences[right_mask + 1];
        const right_values = {position_3 for position_3 in [1..4] if right_mask / weights[position_3] % 2};
        const expected_union = {position_4 for position_4 in [1..4] if (position_4 in left_values) || (position_4 in right_values)};
        const expected_common = {position_5 for position_5 in [1..4] if (position_5 in left_values) && (position_5 in right_values)};
        $seq_utils:tolist($seq_utils:union(left, right)) == expected_union || raise(E_INVARG, "union");
        $seq_utils:tolist($seq_utils:intersection(left, right)) == expected_common || raise(E_INVARG, "intersection");
      endfor
      $seq_utils:size(left) == length(left_values) || raise(E_INVARG, "size");
      $seq_utils:tolist($seq_utils:complement(left, 1, 4)) == {position_6 for position_6 in [1..4] if !(position_6 in left_values)} || raise(E_INVARG, "complement");
      suspend(0);
    endfor
    $seq_utils:union(@all_sequences) == {1, 5} || raise(E_INVARG, "many-way heap merge");
    $seq_utils:union({10, 12}, {1, 3}, {2, 8}, {8, 10}, {20}) == {1, 12, 20} || raise(E_INVARG, "overlap and open upper");
    $seq_utils:intersection({}, {1, 5}) == {} || raise(E_INVARG);
    $seq_utils:from_list({2, 1, 1, 2}) == {1, 3} || raise(E_INVARG, "duplicate members");
    $seq_utils:from_string("1, 2..4, 7, 7, 9..8") == {1, 5, 7, 8} || raise(E_INVARG);
    $seq_utils:from_string("bad") == E_INVARG || raise(E_INVARG);
    $seq_utils:tostr({1, 5, 7, 8}) == "1..4, 7" || raise(E_INVARG);
    $seq_utils:first({}) == E_NONE && $seq_utils:last({}) == E_NONE || raise(E_INVARG);
    $seq_utils:last({$maxint}) == $maxint && $seq_utils:size({$maxint}) == 1 || raise(E_INVARG, "upper limit");
    $seq_utils:tolist({$maxint - 2}) == {$maxint - 2, $maxint - 1, $maxint} || raise(E_INVARG);
    $seq_utils:size({$minint}) == 4294967296 || raise(E_INVARG, "wide count");
    return true;
  endmethod
  method test_collection_sequence_transforms owner: #2
    "Compare insertion/deletion transforms with explicit integer positions, including matching endpoints.";
    const weights = {1, 2, 4, 8};
    for source_mask in [0..15]
      const original = {position_7 for position_7 in [1..4] if source_mask / weights[position_7] % 2};
      const sequence = $seq_utils:from_list(original);
      for insertion_mask in [0..15]
        const inserted = {position_8 for position_8 in [1..4] if insertion_mask / weights[position_8] % 2};
        const insert_sequence = $seq_utils:from_list(inserted);
        let expected = {};
        for item in (original)
          let shifted = item;
          for gap in (inserted)
            gap <= shifted && (shifted = shifted + 1);
          endfor
          expected = {@expected, shifted};
        endfor
        const expanded = $seq_utils:expand(sequence, insert_sequence);
        $seq_utils:tolist(expanded) == expected || raise(E_INVARG, "expand", {original, inserted, expanded, expected});
        $seq_utils:tolist($seq_utils:expand(sequence, insert_sequence, true)) == sort($set_utils:union(expected, inserted)) || raise(E_INVARG, "include");
        $seq_utils:contract(expanded, insert_sequence) == sequence || raise(E_INVARG, "contract inverse");
      endfor
      for count in [0..5]
        const take = min(count, length(original));
        $seq_utils:tolist($seq_utils:firstn(sequence, count)) == original[1..take] || raise(E_INVARG, "firstn");
        $seq_utils:tolist($seq_utils:lastn(sequence, count)) == original[length(original) - take + 1..$] || raise(E_INVARG, "lastn");
      endfor
      suspend(0);
    endfor
    $seq_utils:add({1, 3, 5, 7}, 3, 4) == {1, 7} || raise(E_INVARG);
    $seq_utils:remove({1, 7}, 3, 4) == {1, 3, 5, 7} || raise(E_INVARG);
    $seq_utils:add({}, 3) == {3} && $seq_utils:remove({1}, 3) == {1, 3} || raise(E_INVARG);
    $seq_utils:firstn({$maxint - 2}, 10) == {$maxint - 2} || raise(E_INVARG);
    $seq_utils:tolist($seq_utils:lastn({1, 3, $maxint - 1}, 3)) == {2, $maxint - 1, $maxint} || raise(E_INVARG);
    $seq_utils:extract({2, 4, 9, 12}, {"a", "b", "c", "d"}) == {"b", "c"} || raise(E_INVARG);
    typeof($seq_utils:contains({1, 3}, 2)) == TYPE_BOOL || raise(E_INVARG);
    $seq_utils:for({}, $string_utils, "uppercase") == 0 || raise(E_INVARG);
    return true;
  endmethod
  method test_collection_callbacks owner: #2
    "Exercise captured callbacks, empty lists, short-circuiting, stable keys, and callback error propagation.";
    const offset = 10;
    $list_utils:map({1, 2, 3}, {item} => item + offset) == {11, 12, 13} || raise(E_INVARG);
    $list_utils:map({1, 2, 3}, this.utility_callback) == {5, 8, 11} || raise(E_INVARG, "persisted captures");
    $list_utils:filter({1, 2, 2, 3}, {item} => item % 2 == 0) == {2, 2} || raise(E_INVARG);
    $list_utils:reduce({1, 2, 3}, {accumulator, item} => accumulator * 10 + item, 0) == 123 || raise(E_INVARG);
    $list_utils:reduce({}, {accumulator, item} => accumulator + item, "initial") == "initial" || raise(E_INVARG);
    $list_utils:find_index({0, false, 2}, {item} => typeof(item) == TYPE_BOOL) == 2 || raise(E_INVARG);
    $list_utils:find_index({}, {item} => true) == 0 || raise(E_INVARG);
    $list_utils:any({2, 0}, {item} => 10 / item > 1) || raise(E_INVARG, "any short circuit");
    !$list_utils:all({2, 0}, {item} => 10 / item < 1) || raise(E_INVARG, "all short circuit");
    !$list_utils:any({}, {item} => true) && $list_utils:all({}, {item} => false) || raise(E_INVARG);
    const rows = {{"B", 1}, {"a", 2}, {"b", 3}};
    $list_utils:sort_by(rows, {row} => row[1]) == {{"a", 2}, {"B", 1}, {"b", 3}} || raise(E_INVARG);
    $list_utils:sort_by({"file10", "file2"}, {item} => item, true) == {"file2", "file10"} || raise(E_INVARG);
    $list_utils:sort_by(rows, {row} => row[1], false, true) == {{"B", 1}, {"b", 3}, {"a", 2}} || raise(E_INVARG);
    `$list_utils:map({}, 3) ! E_TYPE' == E_TYPE || raise(E_INVARG);
    `$list_utils:filter(3, {item} => true) ! E_TYPE' == E_TYPE || raise(E_INVARG);
    `$list_utils:map({0}, {item} => 1 / item) ! E_DIV' == E_DIV || raise(E_INVARG);
    return true;
  endmethod
  method test_collection_callback_permissions owner: #2
    "Every closure utility reduces authority before a callback reads a wizard-private property.";
    const target = this;
    const unprivileged = this.test_player;
    const probe = {item} => target.utility_private;
    const reducer = {accumulator, item} => target.utility_private;
    set_task_perms(unprivileged);
    for method in ({"map", "filter", "find_index", "any", "all", "sort_by"})
      `$list_utils:(method)({1}, probe) ! E_PERM' == E_PERM || raise(E_INVARG, method);
    endfor
    `$list_utils:reduce({1}, reducer, 0) ! E_PERM' == E_PERM || raise(E_INVARG, "reduce");
    return true;
  endmethod
  method test_object_utility_tree owner: #2
    "Preserve traversal order, root inclusion, duplicate suppression, and UUID identity.";
    const root = create($root_class);
    const first = create(root);
    const second = create(root);
    const grandchild = create(first);
    try
      const children = children(root);
      const dfs = children[1] == first ? {root, first, grandchild, second} |
        {root, second, first, grandchild};
      $object_utils:ordered_descendants(root) == dfs || raise(E_INVARG, "preorder");
      for operation in ({"descendants", "descendants_suspended"})
        $object_utils:(operation)(root) == {@children, grandchild} || raise(E_INVARG, operation);
      endfor
      const leaves = children[1] == first ? {grandchild, second} | {second, grandchild};
      for operation in ({"leaves", "leaves_suspended"})
        $object_utils:(operation)(root) == leaves || raise(E_INVARG, operation);
        $object_utils:(operation)(second) == {second} || raise(E_INVARG, "leaf root");
      endfor
      for operation in ({"branches", "branches_suspended"})
        $object_utils:(operation)(root) == {root, first} || raise(E_INVARG, operation);
        $object_utils:(operation)(second) == {} || raise(E_INVARG, "branchless root");
      endfor
      $object_utils:ancestors(grandchild, second) == {first, root, $root_class} ||
        raise(E_INVARG, "ancestor order/deduplication");
      $object_utils:isa(grandchild, root) == true || raise(E_INVARG, "isa boolean");
      $object_utils:isa(root, grandchild) == false || raise(E_INVARG, "inverse isa");
      $object_utils:isoneof(grandchild, {second, root}) == true || raise(E_INVARG, "isoneof");
        $string_utils:literal_object(tostr(grandchild)) == grandchild || raise(E_INVARG, "UUID literal");
      add_verb(root, {player, "rxd", "accept"}, {"this", "none", "this"});
      set_verb_code(root, "accept", {"return true;"});
      move(first, root);
      move(second, root);
      move(grandchild, first);
      $object_utils:contains(root, grandchild) == true || raise(E_INVARG, "nested containment");
      $object_utils:contains(root, root) == false || raise(E_INVARG, "self containment");
      $object_utils:locations(grandchild) == {first, root} || raise(E_INVARG, "location chain");
      $object_utils:all_contents(root) == {@root.contents, grandchild} || raise(E_INVARG, "contents order");
      const principal = this.test_programmer;
      `principal:editor_access($object_utils, "disown", first) ! E_PERM' == E_PERM ||
        raise(E_INVARG, "foreign disinheritance");
      root.owner = principal;
      principal:editor_access($object_utils, "disown", first) == true || raise(E_INVARG, "disinheritance");
      parent(first) == $root_class || raise(E_INVARG, "disinheritance target");
    finally
      recycle(grandchild);
      recycle(second);
      recycle(first);
      recycle(root);
    endtry
    return true;
  endmethod

  method test_object_utility_metadata owner: #2
    "Preserve local/inherited lookup and the explicit owner grant for ancestor metadata.";
    const principal = this.test_programmer;
    const root = create($root_class);
    const child = create(root);
    const destination = create($root_class);
    try
      child.owner = principal;
      root.r = 0;
      add_property(root, "private_parent_probe", 7, {player, ""});
      add_property(child, "child_probe", 8, {principal, ""});
      add_property(destination, "child_probe", 9, {player, ""});
      add_verb(root, {player, "xd", "probe*verb"}, {"this", "none", "this"});
      set_verb_code(root, "probeverb", {"return true;"});
      add_verb(child, {principal, "rxd", "probeverb"}, {"this", "none", "this"});
      $object_utils:has_property(child, "private_parent_probe") == true || raise(E_INVARG, "inherited property");
      $object_utils:defines_property(child, "private_parent_probe") == false || raise(E_INVARG, "inherited definition");
      $object_utils:defines_property(root, "private_parent_probe") == true || raise(E_INVARG, "local definition");
      $object_utils:has_readable_property(child, "private_parent_probe") == false || raise(E_INVARG, "private property");
      $object_utils:has_readable_property(child, 'name) == true || raise(E_INVARG, "builtin symbol name");
      $object_utils:has_verb(child, "probeverb") == {child} || raise(E_INVARG, "local empty verb");
      $object_utils:has_callable_verb(child, "probeverb") == {root} || raise(E_INVARG, "nonempty ancestor fallback");
      $object_utils:match_verb(root, "probe*verb") == {root, "probeverb"} || raise(E_INVARG, "wildcard name");
      $object_utils:match_verb(root, "absent_probe") == 0 || raise(E_INVARG, "absent verb");
      $object_utils:defines_verb(root, "probeverb") == true || raise(E_INVARG, "defines boolean");
      $object_utils:has_any_property(child) == true || raise(E_INVARG, "has property boolean");
      for operation in ({"all_properties", "all_properties_suspended"})
        const names = principal:editor_access($object_utils, operation, child);
        'private_parent_probe in names || raise(E_INVARG, "owner grant lost");
        names[$] == 'child_probe || raise(E_INVARG, "ancestor-first names");
      endfor
      !('private_parent_probe in principal:editor_access($object_utils, "findable_properties", child)) ||
        raise(E_INVARG, "findable leaked unreadable ancestor");
      const owned = principal:editor_access($object_utils, "owned_properties", child, player);
      ('child_probe in owned && !('private_parent_probe in owned)) ||
        raise(E_INVARG, "nonwizard selected foreign principal");
      principal:editor_access($object_utils, "accessible_verbs", root) == {E_PERM} ||
        raise(E_INVARG, "private verb name leaked");
      principal:editor_access($object_utils, "accessible_props", root) == {E_PERM} ||
        raise(E_INVARG, "private property name leaked");
      $object_utils:property_conflicts(child, destination) == {{'child_probe, child}} ||
        raise(E_INVARG, "property conflict grouping");
      principal:editor_access($object_utils, "property_conflicts", root, destination) == E_PERM ||
        raise(E_INVARG, "foreign conflict scan permitted");
      $object_utils:descendants_with_property_suspended(root, "child_probe") == {child} ||
        raise(E_INVARG, "first defining descendants");
      $object_utils:descendants_with_property_suspended(child, "private_parent_probe") == {child} ||
        raise(E_INVARG, "inherited property branch root");
      principal:editor_access($object_utils, "descendants_with_property_suspended", root, "child_probe") == E_PERM ||
        raise(E_INVARG, "foreign definition scan permitted");
    finally
      recycle(child);
      recycle(root);
      recycle(destination);
    endtry
    return true;
  endmethod

  method test_object_utility_commits owner: #2
    "A deterministic budget-yield hook commits, revokes root ownership, then resumes the scan.";
    const original = verb_code($command_utils, "suspend_if_needed");
    const root = create($root_class);
    const child = create(root);
    const principal = this.test_programmer;
    try
      child.owner = principal;
      root.r = 0;
      add_property(root, "hidden_after_commit", 1, {player, ""});
      add_property(child, "owned_before_commit", 1, {principal, ""});
      set_verb_code($command_utils, "suspend_if_needed", {
        "const target = #100.tx_probe;",
        "if (typeof(target) == TYPE_OBJ) #100.tx_probe = 0; suspend(0); target.owner = #2; endif",
        "return false;"});
      this.tx_probe = child;
      const names = principal:editor_access($object_utils, "all_properties_suspended", child);
      !('hidden_after_commit in names) || raise(E_INVARG, "stale owner grant after commit");
      'owned_before_commit in names || raise(E_INVARG, "lost previously authorized metadata");
      child.owner = principal;
      this.tx_probe = child;
      principal:editor_access($object_utils, "property_conflicts", child, $root_class) == {} ||
        raise(E_INVARG, "single-object conflict scan");
      const leaf = create(child);
      try
        this.tx_probe = child;
        principal:editor_access($object_utils, "property_conflicts", child, $root_class) == E_PERM ||
          raise(E_INVARG, "stale conflict grant after commit");
        child.owner = principal;
        this.tx_probe = child;
        principal:editor_access($object_utils, "descendants_with_property_suspended", child, "absent") == E_PERM ||
          raise(E_INVARG, "stale root grant after commit");
      finally
        recycle(leaf);
      endtry
    finally
      set_verb_code($command_utils, "suspend_if_needed", original);
      this.tx_probe = 0;
      recycle(child);
      recycle(root);
    endtry
    return true;
  endmethod

  method test_string_utility_matching owner: #2
    "Exact matches beat prefixes, repeated aliases do not create ambiguity, and case rules remain explicit.";
    const first = create($thing);
    const second = create($thing);
    try
      first.name = "lamp";
      first.aliases = {"lamp", "light"};
      second.name = "lamplight";
      second.aliases = {"lamp", "lantern"};
      for operation in ({"match", "match_suspended"})
        $string_utils:(operation)("lamp", {first, second}, "name") == first || raise(E_INVARG, "exact priority");
        $string_utils:(operation)("lam", {first, second}, "name") == $ambiguous_match || raise(E_INVARG, "ambiguous prefix");
        $string_utils:(operation)("LAMP", {first, first}, "aliases") == first || raise(E_INVARG, "duplicate object");
        $string_utils:(operation)("lamp", {first, second}, "aliases") == $ambiguous_match || raise(E_INVARG, "ambiguous exact");
        $string_utils:(operation)("absent", {first, second}, "name") == $failed_match || raise(E_INVARG, "absent match");
        $string_utils:(operation)("", {first}, "name") == $nothing || raise(E_INVARG, "empty match");
      endfor
      $string_utils:match_string("Jack waves to Jill", "* waves to *") == {"Jack", "Jill"} || raise(E_INVARG, "captures");
      $string_utils:match_string("ab", "AB", true) == 0 || raise(E_INVARG, "boolean case option");
      $string_utils:match_string("ab", "AB") == 1 || raise(E_INVARG, "case insensitive wildcard");
      $string_utils:find_prefix("lamp", {"lamp", "lamplight"}) == $ambiguous_match || raise(E_INVARG, "prefix contract");
      $string_utils:match_stringlist("lamp", {"lamp", "lamplight"}) == 1 || raise(E_INVARG, "string exact priority");
      $string_utils:match_stringlist("lamp", {"lamp", "lamp"}) == $ambiguous_match || raise(E_INVARG, "string duplicates");
      $string_utils:index_delimited("lamplight lamp", "lamp") == 11 || raise(E_INVARG, "word boundary");
      $string_utils:common("Abacus", "abandon") == 3 || raise(E_INVARG, "common prefix");
    finally
      recycle(first);
      recycle(second);
    endtry
    return true;
  endmethod

  method test_string_utility_formatting owner: #2
    "Check padding boundaries, literal trim characters, large numbers, and escaped output.";
    for sample in ({{5, "ab", "ababa"}, {-5, "ab", "babab"}, {0, "ab", ""}})
      $string_utils:space(sample[1], sample[2]) == sample[3] || raise(E_INVARG, "padding anchor");
    endfor
    $string_utils:space(-1001) == E_INVARG || raise(E_INVARG, "negative padding limit");
    $string_utils:space(1, "") == E_INVARG || raise(E_INVARG, "empty padding");
    $string_utils:left("abc", -2) == "ab" || raise(E_INVARG, "left truncation");
    $string_utils:right("abc", -2) == "bc" || raise(E_INVARG, "right truncation");
    $string_utils:center("x", 4) == " x  " || raise(E_INVARG, "center rounding");
    $string_utils:trim("]hello]", "]") == "hello" || raise(E_INVARG, "literal trim");
    $string_utils:triml("^^x^^", "^") == "x^^" || raise(E_INVARG, "left trim");
    $string_utils:trimr("--x--", "-") == "--x" || raise(E_INVARG, "right trim");
    $string_utils:uppercase("aBz") == "ABZ" || raise(E_INVARG, "uppercase");
    $string_utils:reverse("aé🙂") == "🙂éa" || raise(E_INVARG, "Unicode reversal");
    $string_utils:english_list({"a", "b", "c"}) == "a, b, and c" || raise(E_INVARG, "English list");
    $string_utils:from_seconds(86400) == "a day" || raise(E_INVARG, "day boundary");
    $string_utils:from_seconds(3600) == "an hour" || raise(E_INVARG, "hour boundary");
    $string_utils:from_seconds(60) == "a minute" || raise(E_INVARG, "minute boundary");
    $string_utils:english_number(1000000000000) == "one trillion" || raise(E_INVARG, "wide number");
    $string_utils:english_number(-9223372036854775807 - 1) ==
      "negative nine quintillion two hundred twenty-three quadrillion three hundred seventy-two trillion thirty-six billion eight hundred fifty-four million seven hundred seventy-five thousand eight hundred eight" || raise(E_INVARG, "minimum integer");
    $string_utils:group_number(-9223372036854775807 - 1) == "-9,223,372,036,854,775,808" || raise(E_INVARG, "minimum grouping");
    $string_utils:group_number(1234.5, 2) == "1,234.50" || raise(E_INVARG, "float grouping");
    $string_utils:group_number(12000.0, 2, true) == "1.2e4" || raise(E_INVARG, "scientific grouping");
    $string_utils:ordinal(-113) == "-113th" || raise(E_INVARG, "ordinal");
    $string_utils:english_ordinal(-122) == "negative one hundred twenty-second" || raise(E_INVARG, "English ordinal");
    const text = "a\"b\\c";
    $string_utils:from_value(text, true) == toliteral(text) || raise(E_INVARG, "quoted value");
    $string_utils:abbreviated_value(text) == toliteral(text) || raise(E_INVARG, "abbreviated quotes");
    $string_utils:from_value({1, {2}}, true, 1) == "{1, {...}}" || raise(E_INVARG, "list depth");
    $string_utils:from_value_suspended({1, {2}}, true, -1) == "{1, {2}}" || raise(E_INVARG, "suspended depth");
    $string_utils:columnize({1, 2, 3, 4}, 2, 9) == $string_utils:columnize_suspended(0, {1, 2, 3, 4}, 2, 9) || raise(E_INVARG, "columns");
    return true;
  endmethod

  method test_string_utility_parsing owner: #2
    "Check quoted command arguments, safe modern literals, prefixes, and balanced expressions.";
    const text = "  one \"two three\" four\\ five \"\" ";
    $string_utils:words(text) == {"one", "two three", "four five", ""} || raise(E_INVARG, "command words");
    const spans = $string_utils:word_start(text);
    { $string_utils:words(text[span[1]..span[2]])[1] for span in (spans)} ==
      $string_utils:words(text) || raise(E_INVARG, "word spans");
    $string_utils:first_word(" \"one two\"   three") == {"one two", "three"} || raise(E_INVARG, "first word");
    $string_utils:words("trailing\\") == {"trailing"} || raise(E_INVARG, "trailing escape");
    for text in ({"1.2", " -2. ", "2e3", ".2e-3"})
      $string_utils:is_float(text) == true || raise(E_INVARG, "valid float");
    endfor
    for text in ({"1.2junk", "junk2e3", "3", "", "1e"})
      $string_utils:is_float(text) == false || raise(E_INVARG, "invalid float");
    endfor
    $string_utils:is_integer(" +123 ") == true || raise(E_INVARG, "integer boolean");
    $string_utils:to_value("+123") == {true, 123} || raise(E_INVARG, "signed literal");
    const value = ['flag -> true, 'items -> {#0, "quoted", false}];
    $string_utils:to_value(toliteral(value)) == {true, value} || raise(E_INVARG, "modern literal");
    $string_utils:prefix_to_value(toliteral(value) + " rc") == {" rc", value} || raise(E_INVARG, "map prefix");
    $string_utils:prefix_to_value("\"quoted\" rc") == {" rc", "quoted"} || raise(E_INVARG, "string prefix");
    $string_utils:prefix_to_value(" -17 rc") == {" rc", -17} || raise(E_INVARG, "scalar prefix");
    $string_utils:to_value("1 + 2")[1] == false || raise(E_INVARG, "expression evaluated");
    $string_utils:to_value("#0:recycle()")[1] == false || raise(E_INVARG, "call evaluated");
    $string_utils:end_expression("{1, \"}\"} rest") == 8 || raise(E_INVARG, "balanced expression");
    $string_utils:end_expression("{1]") == 0 || raise(E_INVARG, "mismatched expression");
    $string_utils:inside_quotes("\"abc\\\\\"") == false || raise(E_INVARG, "escaped backslashes");
    $string_utils:inside_quotes("\"abc\\\"") == true || raise(E_INVARG, "escaped quote");
    const parsed = $string_utils:parse_command("  put lamp in box", this.test_player);
    parsed[1] == "put" && parsed[2][2] == "lamp" && parsed[4][2] == "box" || raise(E_INVARG, "command tuple");
    parsed[5] == {{"lamp", "in", "box"}, "lamp in box"} || raise(E_INVARG, "command arguments");
    return true;
  endmethod

  method test_string_utility_substitution owner: #2
    "Check parallel replacements, regex progress, literal quoting, and explicit pronoun arguments.";
    $string_utils:substitute("hoahooaho", {{"ho", "XhooX"}, {"hoo", "mama"}}) == "XhooXamamaaXhooX" || raise(E_INVARG, "parallel substitution");
    $string_utils:substitute("Cc: banana", {{"a", "b"}, {"b", "c"}, {"c", "a"}}, true) == "Ca: cbnbnb" || raise(E_INVARG, "case-sensitive substitution");
    $string_utils:substitute_delimited("a cat catfish cat", {{"cat", "dog"}}) == "a dog catfish dog" || raise(E_INVARG, "delimited substitution");
    `$string_utils:substitute("abc", {{"", "x"}}) ! E_INVARG' == E_INVARG || raise(E_INVARG, "empty substitution target");
    $string_utils:index_all("banana", "ana") == {2} || raise(E_INVARG, "nonoverlapping positions");
    $string_utils:index_all("abc", "") == {} || raise(E_INVARG, "empty target progress");
    $string_utils:strip_all_but_seq("ab12cd34", "[0-9]+") == "1234" || raise(E_INVARG, "regex extraction");
    $string_utils:strip_all_but_seq("aaa", "^a") == "a" || raise(E_INVARG, "anchor preservation");
    $string_utils:strip_all_but_seq("bbb", "a*") == "" || raise(E_INVARG, "zero width progress");
    const literal = "a[b].*%$";
    match(literal, "^" + $string_utils:regexp_quote(literal) + "$") != {} || raise(E_INVARG, "regex quoting");
    $string_utils:pronoun_sub($string_utils:pronoun_quote("%n %% %s")) == "%n %% %s" || raise(E_INVARG, "pronoun quoting");
    const who = this.test_player;
    const direct = this.test_room;
    const indirect = this.test_room_two;
    $string_utils:pronoun_sub({"%[#d]", "%[#i]"}, who, this, who.location, direct, indirect) ==
      {tostr(direct), tostr(indirect)} || raise(E_INVARG, "multiline explicit objects");
    $string_utils:pronoun_sub("%[] %[#]", who) == "[] [#]" || raise(E_INVARG, "empty pronoun bracket");
    $string_utils:pronoun_sub("%n", who) == who:title() || raise(E_INVARG, "name pronoun");
    $string_utils:incr_alpha("azz") == "baa" || raise(E_INVARG, "alphabet carry");
    return true;
  endmethod

  method test_numeric_division owner: #2
    "Check floor division, signed remainder, and integer boundaries.";
    for numerator in [-20..20]
      for divisor in ({-7, -3, -1, 1, 3, 7})
        const {quotient, remainder} = $math_utils:divmod(numerator, divisor);
        quotient * divisor + remainder == numerator || raise(E_INVARG, "division reconstruction");
        abs(remainder) < abs(divisor) || raise(E_INVARG, "remainder magnitude");
        (remainder == 0 || (remainder < 0) == (divisor < 0)) || raise(E_INVARG, "remainder sign");
      endfor
    endfor
    const minimum = -9223372036854775807 - 1;
    $math_utils:divmod(minimum, 3) == {-3074457345618258603, 1} || raise(E_INVARG, "wide floor");
    $math_utils:mod(minimum, -1) == 0 || raise(E_INVARG, "minimum remainder");
    `$math_utils:div(minimum, -1) ! E_RANGE' == E_RANGE || raise(E_INVARG, "quotient overflow");
    `$math_utils:div(1, 0) ! E_DIV' == E_DIV || raise(E_INVARG, "zero divisor");
    $math_utils:gcd(0, 0) == 0 || raise(E_INVARG, "zero gcd");
    $math_utils:gcd(-24, 18) == 6 || raise(E_INVARG, "signed gcd");
    $math_utils:gcd(minimum, 6) == 2 || raise(E_INVARG, "minimum gcd");
    `$math_utils:gcd(minimum, 0) ! E_RANGE' == E_RANGE || raise(E_INVARG, "gcd overflow");
    $math_utils:lcm(0, 0) == 0 || raise(E_INVARG, "zero lcm");
    $math_utils:lcm(-24, 18) == 72 || raise(E_INVARG, "signed lcm");
    $math_utils:are_relatively_prime(3, 4) == true || raise(E_INVARG, "coprime boolean");
    return true;
  endmethod

  method test_numeric_series owner: #2
    "Check counts, series, integer roots, negative rounding, and primality contracts.";
    $math_utils:factorial(0) == 1 || raise(E_INVARG, "zero factorial");
    $math_utils:factorial(20) == 2432902008176640000 || raise(E_INVARG, "wide factorial");
    `$math_utils:factorial(21) ! E_RANGE' == E_RANGE || raise(E_INVARG, "factorial overflow");
    $math_utils:combinations(66, 33) == 7219428434016265740 || raise(E_INVARG, "wide binomial");
    $math_utils:combinations(4, 0) == 1 || raise(E_INVARG, "empty combination");
    $math_utils:permutations(4, 0) == 1 || raise(E_INVARG, "empty permutation");
    $math_utils:permutations(10, 3) == 720 || raise(E_INVARG, "permutation");
    $math_utils:fibonacci(10) == {0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55} || raise(E_INVARG, "Fibonacci");
    $math_utils:geometric(2, 0) == 1 || raise(E_INVARG, "zero order");
    `$math_utils:exp(9223372036854775807, 2) ! E_RANGE' == E_RANGE || raise(E_INVARG, "exponential overflow");
    $math_utils:geometric(2, 3) == 15 || raise(E_INVARG, "geometric sum");
    $math_utils:pow(2, 10) == 1024 || raise(E_INVARG, "power");
    $math_utils:sqrt(9223372030926249000) == 3037000498 || raise(E_INVARG, "below square");
    $math_utils:sqrt(9223372030926249001) == 3037000499 || raise(E_INVARG, "exact square");
    $math_utils:sqrt(9223372036854775807) == 3037000499 || raise(E_INVARG, "maximum root");
    $math_utils:norm(3000000000, 4000000000) == 5000000000 || raise(E_INVARG, "scaled norm");
    $math_utils:norm(3, 4) == 5 || raise(E_INVARG, "norm");
    for pair in ({{-8, -10}, {-5, 0}, {-3, 0}, {5, 10}, {8, 10}})
      $math_utils:round(pair[1], 10) == pair[2] || raise(E_INVARG, "round ties upward");
    endfor
    $math_utils:parts(-1, 8) == {0, -12500} || raise(E_INVARG, "decimal parts");
    $math_utils:simpson({0, 2}, {0, 1, 4}) == {2, 66666} || raise(E_INVARG, "Simpson integer");
    abs($math_utils:simpson({0, 2}, {0, 1, 4}, true) - 8.0 / 3.0) < 1e-12 || raise(E_INVARG, "Simpson float");
    $math_utils:exp(1, 5) == {2, 71666} || raise(E_INVARG, "Taylor exponential");
    $math_utils:aexp(0) == 10000 || raise(E_INVARG, "scaled exponential");
    $math_utils:mean({1, 2, 3}) == 2 || raise(E_INVARG, "mean");
    $math_utils:sum_float() == 0.0 || raise(E_INVARG, "empty float sum");
    for number in ({2, 3, 97, 104729, 2147483647})
      $math_utils:is_prime(number) == true || raise(E_INVARG, "prime boolean");
    endfor
    for number in ({-7, 0, 1, 4, 99})
      $math_utils:is_prime(number) == false || raise(E_INVARG, "composite boolean");
    endfor
    return true;
  endmethod

  method test_numeric_bits_random owner: #2
    "Check the legacy 32-bit wrappers independently of native integer width, plus random bounds.";
    $math_utils:AND(-1, 2147483648) == -2147483648 || raise(E_INVARG, "signed AND");
    $math_utils:OR(2147483648, 1) == -2147483647 || raise(E_INVARG, "signed OR");
    $math_utils:XOR(-1, 1) == -2 || raise(E_INVARG, "signed XOR");
    $math_utils:NOT(0) == -1 || raise(E_INVARG, "signed NOT");
    $math_utils:AND(4294967296, -1) == 0 || raise(E_INVARG, "low 32 bits");
    const bits = $math_utils:BLFromInt(-1);
    length(bits) == 32 && $list_utils:all(bits, {bit} => typeof(bit) == TYPE_INT && bit == 1) || raise(E_INVARG, "integer bit digits");
    $math_utils:IntFromBL(bits) == 4294967295 || raise(E_INVARG, "unsigned bits");
    $math_utils:base_conversion("FF", 16, 2) == "11111111" || raise(E_INVARG, "base conversion");
    $math_utils:base_conversion("z", 62, 10, true) == "61" || raise(E_INVARG, "base case");
    $math_utils:base_conversion("2", 2, 10) == E_INVARG || raise(E_INVARG, "invalid digit");
    for attempt in [1..50]
      const negative = $math_utils:random(-10);
      negative >= -10 && negative <= 0 || raise(E_INVARG, "negative random bounds");
      const offset = $math_utils:random_range(3, 10);
      offset >= 7 && offset <= 13 || raise(E_INVARG, "random range bounds");
    endfor
    for attempt in [1..20]
      $math_utils:random(9223372036854775807) >= 0 || raise(E_INVARG, "maximum bound");
      $math_utils:random(-9223372036854775807 - 1) <= 0 || raise(E_INVARG, "minimum bound");
      const wide = $math_utils:random_range(9223372036854775807);
      wide != -9223372036854775807 - 1 || raise(E_INVARG, "wide centered range");
    endfor
    $math_utils:random(0) == 0 || raise(E_INVARG, "zero random");
    return true;
  endmethod

  method test_numeric_trig_conversion owner: #2
    "Check scaled degrees, floating radians, coordinate round trips, and temperature offsets.";
    $math_utils:sin(30) == 5000 || raise(E_INVARG, "scaled sine");
    $math_utils:cos(180) == -10000 || raise(E_INVARG, "scaled cosine");
    $math_utils:tan(-45) == -10000 || raise(E_INVARG, "scaled tangent");
    `$math_utils:tan(90) ! E_DIV' == E_DIV || raise(E_INVARG, "tangent singularity");
    $math_utils:sin({29, 60}) == 5000 || raise(E_INVARG, "degree minute pair");
    $math_utils:asin(-5000) == {-30, 0} || raise(E_INVARG, "inverse sine");
    $math_utils:atan(-10000) == {-45, 0} || raise(E_INVARG, "negative inverse tangent");
    abs($math_utils:sin($math_utils.pi / 2.0) - 1.0) < 1e-12 || raise(E_INVARG, "radian sine");
    abs($math_utils:rad2deg($math_utils:deg2rad(27)) - 27.0) < 1e-12 || raise(E_INVARG, "angle conversion");
    for point in ({{3, 4}, {-3, 4}, {-3, -4}, {3, -4}, {0, 5}, {0, 0}})
      const polar = $convert_utils:rect_to_polar(@point);
      abs(polar[1] - (point == {0, 0} ? 0.0 | 5.0)) < 1e-12 || raise(E_INVARG, "polar radius");
      const rect = $convert_utils:polar_to_rect(@polar);
      abs(rect[1] - tofloat(point[1])) < 1e-12 && abs(rect[2] - tofloat(point[2])) < 1e-12 || raise(E_INVARG, "polar round trip");
    endfor
    $convert_utils:C_to_K(0) == 273.15 || raise(E_INVARG, "Celsius offset");
    abs($convert_utils:K_to_C(273.15)) < 1e-12 || raise(E_INVARG, "kelvin offset");
    $convert_utils:F_to_C(32) == 0.0 || raise(E_INVARG, "Fahrenheit freezing");
    $convert_utils:C_to_F(100) == 212.0 || raise(E_INVARG, "Celsius boiling");
    abs($convert_utils:dms_to_dd(@$convert_utils:dd_to_dms(-12.345)) + 12.345) < 1e-12 || raise(E_INVARG, "signed angular components");
    return true;
  endmethod

  method test_unit_conversion owner: #2
    "Check catalog conversions, products, quotients, powers, multiword units, and dimensional errors.";
    for sample in ({{"kilowatt hours", "joules", 3600000.0}, {"100 kg m/sec2", "newtons", 100.0}, {"cm3", "m3", 1e-6}, {"kilodecameter", "m", 10000.0}, {"microns", "m", 1e-6}, {"fluid ounces", "floz", 1.0}, {"1|2 meter", "cm", 50.0}, {"m0", "1", 1.0}, {"m/s/s", "m", 1.0}})
      const converted = $convert_utils:convert(sample[1], sample[2]);
      typeof(converted) == TYPE_FLOAT || raise(E_INVARG, "unit parse", sample);
      abs(converted - sample[3]) <= abs(sample[3]) * 1e-12 || raise(E_INVARG, "unit factor", {sample, converted});
    endfor
    $convert_utils:convert("junk", "meters") == {0, "junk"} || raise(E_INVARG, "unknown source");
    $convert_utils:convert("m", "basic_units")[1] == 0 || raise(E_INVARG, "non-unit property");
    $convert_utils:convert("m", "s") == {1, {1.0, "m"}, {1.0, "s"}} || raise(E_INVARG, "dimensional mismatch");
    return true;
  endmethod

  method test_time_formats owner: #2
    "Check date/clock formats, duration parsing, and substitutions without depending on host timezone.";
    const stamp = "Thu Jan  1 00:03:09 1970 UTC";
    $time_utils:day(stamp) == "Thursday" || raise(E_INVARG, "day name");
    $time_utils:month(stamp) == "January" || raise(E_INVARG, "month name");
    $time_utils:ampm(stamp, 3) == "12:03:09 a.m." || raise(E_INVARG, "midnight format");
    $time_utils:ampm(stamp, 1) == "12 a.m." || raise(E_INVARG, "hour precision");
    $time_utils:mmddyy(stamp) == "01/01/70" || raise(E_INVARG, "short date");
    $time_utils:ddmmyyyy("Sat Feb 29 12:00:00 2020 UTC", "-") == "29-02-2020" || raise(E_INVARG, "long date");
    $time_utils:to_seconds("23:59:59") == 86399 || raise(E_INVARG, "clock seconds");
    $time_utils:to_seconds("24:00:00") == E_INVARG || raise(E_INVARG, "invalid clock");
    $time_utils:dhms(-90061) == "-1:01:01:01" || raise(E_INVARG, "negative duration");
    $time_utils:dhms(-9223372036854775807 - 1) == "-106751991167300:15:30:08" || raise(E_INVARG, "minimum duration");
    $time_utils:english_time(90061, stamp) == "1 day, 1 hour, 1 minute, and 1 second" || raise(E_INVARG, "English duration");
    $time_utils:english_time(12622780800, stamp) == "400 years" || raise(E_INVARG, "calendar cycle");
    $time_utils:english_time(2505600, "Tue Feb  1 00:00:00 2000 UTC") == "1 month" || raise(E_INVARG, "leap month duration");
    $time_utils:english_time(2505600, "Mon Feb  1 00:00:00 2100 UTC") == "1 month and 1 day" || raise(E_INVARG, "century duration");
    $time_utils:parse_english_time_interval("an hour, and 2 minutes") == 3720 || raise(E_INVARG, "English interval");
    $time_utils:parse_english_time_interval("3", "secs", "no", "days") == 3 || raise(E_INVARG, "argument pairs");
    $time_utils:parse_english_time_interval("002 minutes") == 120 || raise(E_INVARG, "leading zero amount");
    $time_utils:parse_english_time_interval("2 wombats") == E_INVARG || raise(E_INVARG, "unknown duration unit");
    $time_utils:parse_english_time_interval("9223372036854775807 days") == E_RANGE || raise(E_INVARG, "duration overflow");
    const now = time();
    const local = ctime(now);
    const clock = local[12..19];
    $time_utils:time_sub("$H:$M:$S", now) == clock || raise(E_INVARG, "clock substitution");
    $time_utils:time_sub("$Q$$$", now) == "$" || raise(E_INVARG, "unknown and trailing macros");
    $time_utils:seconds_until_time(clock, now) == 0 || raise(E_INVARG, "local clock delta");
    $time_utils:to_seconds(ctime($time_utils:dst_midnight(now))[12..19]) == 0 || raise(E_INVARG, "local midnight");
    return true;
  endmethod

  method test_time_calendar owner: #2
    "Check Gregorian conversion against fixed UTC vectors, including century rules and pre-epoch dates.";
    for sample in ({{"Mon Jan  1 00:00:00 0001 UTC", -62135596800, {1, 1, 1}},
      {"Wed Feb 28 00:00:00 0001 UTC", -62130585600, {1, 2, 28}},
      {"Thu Mar  1 00:00:00 0001 UTC", -62130499200, {1, 3, 1}},
      {"Mon Dec 31 00:00:00 0001 UTC", -62104147200, {1, 12, 31}},
      {"Sat Jan  1 00:00:00 1600 UTC", -11676096000, {1600, 1, 1}},
      {"Mon Feb 28 00:00:00 1600 UTC", -11671084800, {1600, 2, 28}},
      {"Wed Mar  1 00:00:00 1600 UTC", -11670912000, {1600, 3, 1}},
      {"Sun Dec 31 00:00:00 1600 UTC", -11644560000, {1600, 12, 31}},
      {"Mon Jan  1 00:00:00 1900 UTC", -2208988800, {1900, 1, 1}},
      {"Wed Feb 28 00:00:00 1900 UTC", -2203977600, {1900, 2, 28}},
      {"Thu Mar  1 00:00:00 1900 UTC", -2203891200, {1900, 3, 1}},
      {"Mon Dec 31 00:00:00 1900 UTC", -2177539200, {1900, 12, 31}},
      {"Wed Jan  1 00:00:00 1969 UTC", -31536000, {1969, 1, 1}},
      {"Fri Feb 28 00:00:00 1969 UTC", -26524800, {1969, 2, 28}},
      {"Sat Mar  1 00:00:00 1969 UTC", -26438400, {1969, 3, 1}},
      {"Wed Dec 31 00:00:00 1969 UTC", -86400, {1969, 12, 31}},
      {"Thu Jan  1 00:00:00 1970 UTC", 0, {1970, 1, 1}},
      {"Sat Feb 28 00:00:00 1970 UTC", 5011200, {1970, 2, 28}},
      {"Sun Mar  1 00:00:00 1970 UTC", 5097600, {1970, 3, 1}},
      {"Thu Dec 31 00:00:00 1970 UTC", 31449600, {1970, 12, 31}},
      {"Sat Jan  1 00:00:00 2000 UTC", 946684800, {2000, 1, 1}},
      {"Mon Feb 28 00:00:00 2000 UTC", 951696000, {2000, 2, 28}},
      {"Wed Mar  1 00:00:00 2000 UTC", 951868800, {2000, 3, 1}},
      {"Sun Dec 31 00:00:00 2000 UTC", 978220800, {2000, 12, 31}},
      {"Mon Jan  1 00:00:00 2024 UTC", 1704067200, {2024, 1, 1}},
      {"Wed Feb 28 00:00:00 2024 UTC", 1709078400, {2024, 2, 28}},
      {"Fri Mar  1 00:00:00 2024 UTC", 1709251200, {2024, 3, 1}},
      {"Tue Dec 31 00:00:00 2024 UTC", 1735603200, {2024, 12, 31}},
      {"Fri Jan  1 00:00:00 2100 UTC", 4102444800, {2100, 1, 1}},
      {"Sun Feb 28 00:00:00 2100 UTC", 4107456000, {2100, 2, 28}},
      {"Mon Mar  1 00:00:00 2100 UTC", 4107542400, {2100, 3, 1}},
      {"Fri Dec 31 00:00:00 2100 UTC", 4133894400, {2100, 12, 31}},
      {"Sat Jan  1 00:00:00 2400 UTC", 13569465600, {2400, 1, 1}},
      {"Mon Feb 28 00:00:00 2400 UTC", 13574476800, {2400, 2, 28}},
      {"Wed Mar  1 00:00:00 2400 UTC", 13574649600, {2400, 3, 1}},
      {"Sun Dec 31 00:00:00 2400 UTC", 13601001600, {2400, 12, 31}},
      {"Fri Jan  1 00:00:00 9999 UTC", 253370764800, {9999, 1, 1}},
      {"Sun Feb 28 00:00:00 9999 UTC", 253375776000, {9999, 2, 28}},
      {"Mon Mar  1 00:00:00 9999 UTC", 253375862400, {9999, 3, 1}},
      {"Fri Dec 31 00:00:00 9999 UTC", 253402214400, {9999, 12, 31}}})
      $time_utils:from_ctime(sample[1]) == sample[2] || raise(E_INVARG, "Gregorian timestamp", sample);
      $time_utils:_calendar(sample[2]) == sample[3] || raise(E_INVARG, "Gregorian date", sample);
    endfor
    $time_utils:from_ctime("Tue Feb 29 00:00:00 2000 UTC") == 951782400 || raise(E_INVARG, "leap day timestamp");
    $time_utils:from_ctime("Thu Jan  1 00:00:00 1970 PST") == 28800 || raise(E_INVARG, "fixed PST");
    $time_utils:from_ctime("Thu Jan  1 00:00:00 1970 +0530") == -19800 || raise(E_INVARG, "numeric zone");
    $time_utils:from_ctime("Thu Jan  1 00:00:00 1970 -0330") == 12600 || raise(E_INVARG, "negative numeric zone");
    $time_utils:from_ctime("Mon Feb 29 00:00:00 2100 UTC") == E_DIV || raise(E_INVARG, "invalid century day");
    $time_utils:from_ctime("Thu Jan  1 25:00:00 1970 UTC") == E_DIV || raise(E_INVARG, "invalid ctime clock");
    $time_utils:_calendar(-1) == {1969, 12, 31} || raise(E_INVARG, "negative second");
    return true;
  endmethod

  method test_time_selection owner: #2
    "Check nearest/past/future selection in fixed PST, independent of the host timezone.";
    $time_utils:from_day("Thursday", -1, 28800) == 28800 || raise(E_INVARG, "exact most recent day");
    $time_utils:from_day("Thursday", 1, 28800) == 633600 || raise(E_INVARG, "strict upcoming day");
    $time_utils:from_day(5, -1, 0) == -576000 || raise(E_INVARG, "pre-epoch previous day");
    $time_utils:from_day("Thursday", 0, 0) == 28800 || raise(E_INVARG, "nearest day");
    $time_utils:from_day("T", 0, 0) == E_DIV || raise(E_INVARG, "ambiguous weekday");
    $time_utils:from_month("Jan", -1, 1, 28800) == 28800 || raise(E_INVARG, "exact recent month");
    $time_utils:from_month(1, 1, 1, 28800) == 31564800 || raise(E_INVARG, "upcoming year");
    $time_utils:from_month(1, -1, 1, 0) == -31507200 || raise(E_INVARG, "previous year");
    $time_utils:from_month(1, 0, 1, 0) == 28800 || raise(E_INVARG, "nearest month");
    $time_utils:seconds_until_date(1, 1, "12:00:00", 0, 0) == 72000 || raise(E_INVARG, "date clock delta");
    $time_utils:from_month("Feb", 0, 29, 4107542400) == E_DIV || raise(E_INVARG, "invalid century leap date");
    return true;
  endmethod

  method test_login_site_restrictions owner: #2
    "Check hostname boundaries and overlapping temporary restrictions without changing site policy.";
    const saved = {$login.blacklist, $login.temporary_blacklist, $login.downtimes};
    try
      $login.blacklist = {{}, {}};
      $login.downtimes = {};
      $login.temporary_blacklist = {{}, {{"node.example", time() - 20, 1}, {"*.example", time(), 600}}};
      $login:blacklisted("node.example") == true || raise(E_INVARG, "expired exact entry masked active wildcard");
      $login.blacklist = {{"192.0.2"}, {"example.org", "*.example.net"}};
      for host in ({"192.0.2.10", "example.org", "sub.example.org", "sub.example.net"})
        $login:blacklisted(host) == true || raise(E_INVARG, "blocked host", host);
      endfor
      for host in ({"192.0.20.10", "notexample.org", "example.org.evil", "other.invalid"})
        $login:blacklisted(host) == false || raise(E_INVARG, "host boundary", host);
      endfor
      $login:blacklist_add_temp("192.0.3", time(), 100) == true || raise(E_INVARG, "temporary add");
      $login:blacklisted("192.0.3.9") == true || raise(E_INVARG, "temporary numeric prefix");
      $login:blacklist_remove_temp("192.0.3") == true || raise(E_INVARG, "temporary remove");
      this.test_programmer:editor_access($login, "blacklisted", "example.org") == E_PERM || raise(E_INVARG, "private restriction lookup");
    finally
      $login.blacklist = saved[1];
      $login.temporary_blacklist = saved[2];
      $login.downtimes = saved[3];
    endtry
    return true;
  endmethod

  method test_guest_log_history owner: #2
    "Check bounded guest history, exact connection boundaries, and private access.";
    const guest = create($guest);
    const saved = {$guest_log.connections, $guest_log.max_entries};
    try
      add_verb(guest, {#2, "rxd", "append_log"}, {"none", "none", "none"});
      set_verb_code(guest, "append_log", {"return $guest_log:enter(@args);"});
      $guest_log.connections = {};
      $guest_log.max_entries = 2;
      guest:append_log(true, 100, "host.example");
      guest:append_log(false, 200, "host.example");
      guest:append_log(true, 300, "next.example");
      length($guest_log.connections) == 2 || raise(E_INVARG, "guest log bound");
      $guest_log.connections = {{guest, false, 200, "host.example"}, {guest, true, 100, "host.example"}};
      $guest_log:find(guest, 200) == 0 || raise(E_INVARG, "disconnection instant");
      $guest_log:find(guest, 100) == "host.example" || raise(E_INVARG, "connection instant");
      $guest_log:find(guest, 150) == "host.example" || raise(E_INVARG, "within visit");
      $guest_log:find(guest, 99) == E_NACC || raise(E_INVARG, "before retained history");
      `this.test_programmer:editor_access($guest_log, "find", guest, 150) ! E_PERM' == E_PERM || raise(E_INVARG, "private guest log");
    finally
      $guest_log.connections = saved[1];
      $guest_log.max_entries = saved[2];
      recycle(guest);
    endtry
    return true;
  endmethod

  method test_guest_reset_and_identity owner: #2
    "Reset refusals and mail markers between visits; fingerprint hosts for UUID callers.";
    const guest = create($guest);
    const principal = create($root_class);
    try
      guest.refused_origins = {$nothing};
      guest.refused_actions = {{"page"}};
      guest.refused_until = {time() + 1000};
      guest.refused_extra = {{0}};
      guest.report_refusal = true;
      guest.default_refusal_time = 17;
      guest.page_refused = 123;
      guest.messages_kept = {1};
      guest:do_reset();
      guest.refused_origins == {} && guest.refused_actions == {} && guest.refused_until == {} && guest.refused_extra == {} || raise(E_INVARG, "guest refusal leak");
      guest.messages_kept == {} && guest.page_refused == 0 || raise(E_INVARG, "guest mail/page marker leak");
      guest.default_refusal_time == $guest.default_refusal_time || raise(E_INVARG, "guest default duration leak");
      principal.owner = principal;
      add_verb(principal, {principal, "rxd", "fingerprint"}, {"none", "none", "none"});
      set_verb_code(principal, "fingerprint", {"return args[1]:connection_name_hash(\"xx\");"});
      guest.last_connect_place = "port 7777 from first.example, port 12345";
      const first = principal:fingerprint(guest);
      first == principal:fingerprint(guest) || raise(E_INVARG, "unstable guest fingerprint");
      guest.last_connect_place = "port 7777 from second.example, port 12345";
      first != principal:fingerprint(guest) || raise(E_INVARG, "host fingerprint collision");
    finally
      recycle(guest);
      recycle(principal);
    endtry
    return true;
  endmethod

  method test_refusal_lifecycle owner: #2
    "Preserve everybody refusals during cleanup and keep action/metadata arrays aligned.";
    const who = this.test_programmer;
    const names = {"refused_origins", "refused_actions", "refused_until", "refused_extra"};
    const saved = {who.(name) for name in (names)};
    try
      who.refused_origins = {$nothing};
      who.refused_actions = {{"page"}};
      who.refused_until = {time() + 600};
      who.refused_extra = {{0}};
      who:remove_expired_refusals();
      who.refused_origins == {$nothing} || raise(E_INVARG, "everybody sentinel removed");
      who:refuses_action(this.test_player, "page") == true || raise(E_INVARG, "global refusal predicate");
      who:editor_access(who, "clear_refusals");
      who:editor_access(who, "add_refusal", this.test_player, {"page", "page", "whisper"}, 600, "detail");
      who.refused_actions == {{"page", "whisper"}} && who.refused_extra == {{"detail", "detail"}} || raise(E_INVARG, "duplicate actions");
      who:editor_access(who, "remove_refusal", this.test_player, {"page"}) == 1 || raise(E_INVARG, "remove count");
      who.refused_actions == {{"whisper"}} && who.refused_extra == {{"detail"}} || raise(E_INVARG, "action metadata alignment");
      who.refused_until = {time() - 1};
      const tasks = queued_tasks();
      who:refuses_action(this.test_player, "whisper") == false || raise(E_INVARG, "expired refusal");
      queued_tasks() == tasks || raise(E_INVARG, "refusal query forked cleanup");
      who:remove_expired_refusals();
      who.refused_origins == {} && who.refused_extra == {} || raise(E_INVARG, "expired cleanup");
      who:add_refusal(this.test_player, {"page"}) == E_PERM || raise(E_INVARG, "foreign refusal write");
    finally
      for position in [1..length(names)]
        who.(names[position]) = saved[position];
      endfor
    endtry
    return true;
  endmethod

  method test_refusal_duration_parsing owner: #2
    "Check positive duration prefixes, invalid units, and action-name ambiguity.";
    const who = this.test_programmer;
    who:time_word_to_seconds("nonsense") == 0 || raise(E_INVARG, "unknown unit sentinel");
    who:parse_time_length({"2", "hours", "from"}) == 2 || raise(E_INVARG, "duration prefix");
    who:parse_time_length({"hour", "from"}) == 1 || raise(E_INVARG, "unit prefix");
    who:parse_time_length({"nonsense"}) == 0 || raise(E_INVARG, "invalid duration prefix");
    who:parse_time({"2"}) == 172800 || raise(E_INVARG, "bare day count");
    who:parse_time({"2", "hours"}) == 7200 || raise(E_INVARG, "unit count");
    who:parse_time({"nonsense"}) == E_INVARG || raise(E_INVARG, "invalid duration");
    const parsed = who:parse_refuse_arguments("pages whispers for 2 hours");
    parsed == {$nothing, {"page", "whisper"}, 7200} || raise(E_INVARG, "refusal grammar", parsed);
    who:parse_refuse_arguments("m") == 0 || raise(E_INVARG, "ambiguous action");
    who:parse_refuse_arguments("pages for nonsense") == 0 || raise(E_INVARG, "invalid duration accepted");
    return true;
  endmethod
  method test_mail_resend_arguments owner: #2
    "Resending keeps the original sender and subject while adding resend headers and the supplied body.";
    const box = this.test_mailbox;
    const saved = {box.messages, box.messages_going, box.messages_kept, box.last_msg_date, box.last_used_time};
    try
      box.messages = {};
      box.messages_going = {};
      const result = $mail_agent:resend_message(player, {box}, player, {box}, "Resent subject", {"Resent body"});
      result[1] == 1 || raise(E_INVARG, "resend failed");
      const text = box.messages[$][2];
      (text[4] == "Resent subject" && text[$] == "Resent body") || raise(E_INVARG, "resend changed subject or body");
      const headers = $mail_agent:parse_misc_headers(text, "Resent-By", "Resent-To");
      (headers[3][1] && headers[3][2]) || raise(E_INVARG, "resend headers missing");
    finally
      box.messages = saved[1];
      box.messages_going = saved[2];
      box.messages_kept = saved[3];
      box.last_msg_date = saved[4];
      box.last_used_time = saved[5];
    endtry
    return true;
  endmethod

  method test_mail_sparse_search_masks owner: #2
    "Searches include the first message after each gap in a sequence mask.";
    const box = this.test_mailbox;
    const saved = box.messages;
    try
      box.messages = {{1, {10, "Writer (#2)", "Reader (#2)", "Needle", "", "Needle"}}, {2, {20, "Writer (#2)", "Reader (#2)", "Needle", "", "Needle"}}, {3, {30, "Writer (#2)", "Reader (#2)", "Needle", "", "Needle"}}};
      const mask = {1, 2, 3, 4};
      for name in ({"from_msg_seq", "to_msg_seq", "%from_msg_seq", "%to_msg_seq", "subject_msg_seq", "body_msg_seq"})
        const pattern = name in {"from_msg_seq", "to_msg_seq"} ? {#2} | (name in {"%from_msg_seq", "%to_msg_seq"} ? "(#2)" | "Needle");
        box:(name)(pattern, mask) == mask || raise(E_INVARG, name + " skipped a mask boundary");
      endfor
    finally
      box.messages = saved;
    endtry
    return true;
  endmethod

  method test_mail_sort_metadata owner: #2
    "Date sorting preserves kept messages by identity, discards invalid undo positions, and accepts an empty folder.";
    const box = this.test_mailbox;
    const saved = {box.messages, box.messages_going, box.messages_kept, box.last_msg_date, box.last_used_time};
    try
      box.messages = {{10, {30, "from", "to", "late", "", "body"}}, {20, {10, "from", "to", "early", "", "body"}}};
      box.messages_kept = {1, 2};
      box.messages_going = {{0, {{5, {5, "from", "to", "removed", "", "body"}}}}};
      box:date_sort();
      (box.messages[1][2][4] == "early" && box.messages[2][1] == 2) || raise(E_INVARG, "sort order or numbering");
      (box.messages_kept == {2, 3} && box.messages_going == {} && box.last_msg_date == 30) || raise(E_INVARG, "sort metadata");
      box.messages = {};
      box.messages_kept = {};
      box:date_sort();
      box.last_msg_date == 0 || raise(E_INVARG, "empty sort date");
    finally
      box.messages = saved[1];
      box.messages_going = saved[2];
      box.messages_kept = saved[3];
      box.last_msg_date = saved[4];
      box.last_used_time = saved[5];
    endtry
    return true;
  endmethod

  method test_mail_remove_restore_metadata owner: #2
    "Remove and undo sparse sequences preserve new arrivals, kept flags, and message numbers.";
    const box = this.test_mailbox;
    const saved = {box.messages, box.messages_going, box.messages_kept, box.last_msg_date, box.last_used_time};
    try
      box.messages = { {i * 10, {i * 10, "from", "to", tostr(i), "", "body"}} for i in [1..5] };
      box.messages_going = {};
      box.messages_kept = {1, 2, 5, 6};
      box:rm_message_seq({1, 2, 5, 6});
      (box.messages_kept == {} && box.last_msg_date == 40) || raise(E_INVARG, "remove metadata");
      box:receive_message({60, "from", "to", "arrival", "", "body"});
      box:undo_rmm();
      ($list_utils:slice(box.messages) == {10, 20, 30, 40, 50, 51} && box.messages_kept == {1, 2, 5, 6}) || raise(E_INVARG, "undo lost an arrival or kept marks");
      box:renumber(40) == {6, 4} || raise(E_INVARG, "renumber current pointer");
      box.messages_kept == {1, 2, 5, 6} || raise(E_INVARG, "renumber kept marks");
    finally
      box.messages = saved[1];
      box.messages_going = saved[2];
      box.messages_kept = saved[3];
      box.last_msg_date = saved[4];
      box.last_used_time = saved[5];
    endtry
    return true;
  endmethod

  method test_news_rejected_edition_preserves_state owner: #2
    "Invalid publication must not leave a changed edition after its error is caught.";
    const saved = {$news.messages, $news.current_news, $news.last_news_time};
    try
      $news.messages = {{1, {10, "from", "to", "subject", "", "body"}}};
      $news.current_news = {1, 2};
      $news.last_news_time = 10;
      const error = `$news:set_current_news({2, 3}) ! ANY => E_INVARG';
      typeof(error) == TYPE_ERR || raise(E_INVARG, "invalid edition accepted");
      ($news.current_news == {1, 2} && $news.last_news_time == 10) || raise(E_INVARG, "rejected edition mutated state");
      $news:news_display_seq_full({}) == {0, 0} || raise(E_INVARG, "empty news display");
    finally
      $news.messages = saved[1];
      $news.current_news = saved[2];
      $news.last_news_time = saved[3];
    endtry
    return true;
  endmethod

  method test_mail_list_matching owner: #2
    "Normalize list aliases, preserve prefix ambiguity, and ignore stale private references.";
    const box = this.test_mailbox;
    const who = this.test_programmer;
    const saved = {box.aliases, $news.aliases, who.mail_lists};
    try
      box.aliases = {"batch_mail-one"};
      $news.aliases = {"batch_mail-two"};
      who.mail_lists = {$nothing, box};
      $mail_agent:match("batch-mail-one", who) == box || raise(E_INVARG, "normalized exact match");
      $mail_agent:match("batch_mail-o", who) == box || raise(E_INVARG, "normalized prefix");
      $mail_agent:match("batch-mail", who) == $ambiguous_match || raise(E_INVARG, "prefix ambiguity");
      $mail_agent:match("*", who) == $nothing || raise(E_INVARG, "empty address");
      $mail_agent:match("absent-batch-list", who) == $failed_match || raise(E_INVARG, "missing alias");
      $mail_agent:match(tostr(box), who) == box || raise(E_INVARG, "literal recipient");
      box:set_aliases({"batch-mail_two", "unique-batch-list"}) == false || raise(E_INVARG, "alias collision accepted");
      box.aliases == {"unique-batch-list"} || raise(E_INVARG, "accepted aliases");
    finally
      box.aliases = saved[1];
      $news.aliases = saved[2];
      who.mail_lists = saved[3];
    endtry
    return true;
  endmethod

  method test_mail_access_policy owner: #2
    "Non-list writers and moderation flags must not turn caught type errors into permission grants.";
    const box = this.test_mailbox;
    const who = this.test_player;
    const saved = {box.writers, box.moderated, box.readers};
    try
      box.writers = 0;
      box.moderated = 1;
      box.readers = {};
      box:is_writable_by(who) == false || raise(E_INVARG, "non-list writers granted access");
      box:is_usable_by(who) == false || raise(E_INVARG, "moderation flag granted access");
      box:is_readable_by(who) == false || raise(E_INVARG, "private folder readable");
      box.writers = {who};
      box:is_writable_by(who) == true || raise(E_INVARG, "listed writer denied");
      box:is_usable_by(who) == true || raise(E_INVARG, "writer cannot post");
    finally
      box.writers = saved[1];
      box.moderated = saved[2];
      box.readers = saved[3];
    endtry
    return true;
  endmethod

  method test_news_sort_membership owner: #2
    "Sorting preserves edition membership and clears undo metadata tied to the old order.";
    const names = {"messages", "messages_kept", "messages_going", "last_msg_date", "last_used_time", "current_news", "current_news_going"};
    const saved = {$news.(name) for name in (names)};
    try
      $news.messages = {{10, {30, "from", "to", "late", "", "body"}}, {20, {10, "from", "to", "early", "", "body"}}};
      $news.messages_kept = {1, 2};
      $news.current_news = {1, 2};
      $news.current_news_going = {2, 3};
      $news:date_sort();
      ($news.current_news == {2, 3} && $news.messages_kept == {2, 3}) || raise(E_INVARG, "sort changed membership");
      $news.current_news_going == {} || raise(E_INVARG, "stale edition undo");
      $news:rm_message_seq({2, 3});
      $news.current_news == {} || raise(E_INVARG, "removed article retained");
      $news:undo_rmm();
      $news.current_news == {2, 3} || raise(E_INVARG, "restored article missing");
    finally
      for position in [1..length(names)]
        $news.(names[position]) = saved[position];
      endfor
    endtry
    return true;
  endmethod

  method test_mail_format_repair owner: #2
    "Repair textual headers without dropping address characters or message identity.";
    const box = this.test_mailbox;
    const saved = {box.messages, box.last_msg_date};
    try
      box.messages = {{7, {100, "From: Alice", "To: Bob", "Subject: Old message", "", "Body"}}};
      box:__fix();
      box.messages == {{7, {100, "Alice", "Bob", "Old message", "", "Body"}}} || raise(E_INVARG, "repair changed the address or record");
      box.last_msg_date == 100 || raise(E_INVARG, "repair date metadata");
    finally
      box.messages = saved[1];
      box.last_msg_date = saved[2];
    endtry
    return true;
  endmethod

  method test_mail_folder_defaults owner: #2
    "Sticky folders retain valid objects; missing folders and disabled options use the player.";
    const who = this.test_player;
    const saved = {who.current_folder, who.mail_options, who.current_message};
    try
      who.mail_options = ["sticky" -> true];
      who.current_folder = this.test_mailbox;
      who:current_folder() == this.test_mailbox || raise(E_INVARG, "sticky folder lost");
      who.current_folder = $nothing;
      who:current_folder() == who || raise(E_INVARG, "invalid folder fallback");
      who.current_folder = this.test_mailbox;
      who.mail_options = [];
      who:current_folder() == who || raise(E_INVARG, "disabled sticky folder");
      who.current_message = {0, 0};
      who:set_current_message(this.test_mailbox) == {0, 0} || raise(E_INVARG, "boolean message number");
    finally
      who.current_folder = saved[1];
      who.mail_options = saved[2];
      who.current_message = saved[3];
    endtry
    return true;
  endmethod

  method test_mail_reply_lines owner: #2
    "Included replies preserve complete source lines and Reply-to recipients.";
    const line = "This deliberately long message line must remain a single line in an included reply, with all spaces and trailing content preserved.";
    const message = {time(), "Sender (#102)", "Reader (#101)", "Subject", "Reply-to: Wizard (#2)", "", line};
    const draft = $mail_editor:parse_invoke(2, "@reply", message, {"include"}, {});
    draft[4][$] == "> " + line || raise(E_INVARG, "quoted line wrapped");
    draft[2] == "Re: Subject" || raise(E_INVARG, "reply subject");
    return true;
  endmethod

  method test_mail_selection_authority owner: #2
    "Confirmation validation rejects changed records and a lost read grant.";
    const box = this.test_mailbox;
    const saved = {box.messages, box.readers};
    try
      box.messages = {{1, {10, "from", "to", "subject", "", "body"}}};
      box.readers = {this.test_programmer};
      const snapshot = box:messages_in_seq({1, 2});
      this.test_programmer:editor_access(this.test_programmer, "_mail_selection_unchanged", box, snapshot) == true || raise(E_INVARG, "unchanged selection rejected");
      box.messages[1][2][4] = "changed";
      this.test_programmer:editor_access(this.test_programmer, "_mail_selection_unchanged", box, snapshot) == false || raise(E_INVARG, "changed selection accepted");
      box.messages = snapshot;
      box.readers = {};
      this.test_programmer:editor_access(this.test_programmer, "_mail_selection_unchanged", box, snapshot) == false || raise(E_INVARG, "lost read authority accepted");
    finally
      box.messages = saved[1];
      box.readers = saved[2];
    endtry
    return true;
  endmethod

  method test_mail_sending_state owner: #2
    "False denotes an idle draft; a live task is retained and a dead task marks the draft changed.";
    const editor = $recycler:_create($mail_editor);
    try
      editor.active = {player};
      editor.sending = {false};
      editor.changes = {false};
      editor.times = {0};
      editor:sending(1) == false || raise(E_INVARG, "idle sending marker");
      editor.sending = {task_id()};
      editor:sending(1) == task_id() || raise(E_INVARG, "live sending marker");
      editor.sending = {-1};
      editor:sending(1) == false && editor:changed(1) == true || raise(E_INVARG, "crashed draft not retained");
    finally
      $recycler:_recycle(editor);
    endtry
    return true;
  endmethod

  method test_unbounded_callers_output owner: #2
    "Caller listings preserve long verb names and UUID identities without a screen-width setting.";
    !$object_utils:has_property($server_options, "screen_width") || raise(E_INVARG, "display width retained");
    const object = $recycler:_create($thing);
    try
      const name = "a_very_long_verb_name_that_must_not_be_truncated_in_a_callers_listing";
      const output = $code_utils:callers_text({{object, name, player, object, player, 42}});
      index(output[3], name + "(42)") || raise(E_INVARG, "caller verb truncated");
      index(output[3], tostr(object)) || raise(E_INVARG, "UUID truncated");
    finally
      $recycler:_recycle(object);
    endtry
    return true;
  endmethod

  method test_unsend_unread_selection owner: #2
    "Apply unread and kept filters before the last-count limit, including when the cursor points backward.";
    const who = this.test_player;
    const saved = {who.messages, who.messages_kept, who.current_message};
    try
      who.messages = {{1, {10, "Wizard (#2)", "Reader (#101)", "old", "", "body"}}, {2, {20, "Wizard (#2)", "Reader (#101)", "read", "", "body"}}, {3, {30, "Wizard (#2)", "Reader (#101)", "new", "", "body"}}};
      who.current_message = {1, 20};
      who.messages_kept = {};
      who:_unsend_selection(who, {"unkept:", "from:#2"}, 1) == {{3, 4}} || raise(E_INVARG, "read messages eligible");
      who.messages_kept = {3, 4};
      who:_unsend_selection(who, {"unkept:", "from:#2"}, 1) == {{}} || raise(E_INVARG, "kept message eligible");
    finally
      who.messages = saved[1];
      who.messages_kept = saved[2];
      who.current_message = saved[3];
    endtry
    return true;
  endmethod

  method test_quota_measurement_lifecycle owner: #2
    "Measured UUID objects transfer and recycle without leaving stale owner totals.";
    const who = this.test_programmer;
    const other = this.test_player;
    $quota_utils:initialize_quota(who);
    $quota_utils:initialize_quota(other);
    who.owned_objects = {};
    other.owned_objects = {};
    const item = who:editor_access($recycler, "_create", $thing);
    typeof(item) == TYPE_OBJ || raise(E_INVARG, "quota fixture creation failed");
    try
      const measured = $quota_utils:object_bytes(item);
      measured > 0 || raise(E_INVARG, "object was not measured");
      who.size_quota[2] == measured || raise(E_INVARG, "measurement not charged");
      const summary = $quota_utils:summarize_one_user(who);
      summary[1] == measured || raise(E_INVARG, "summary disagrees with cached measurement");
      $wiz_utils:set_owner(item, other);
      who.size_quota[2] == 0 || raise(E_INVARG, "old owner still charged");
      other.size_quota[2] == measured || raise(E_INVARG, "new owner not charged");
      $recycler:_recycle(item);
      other.size_quota[2] == 0 || raise(E_INVARG, "recycle did not refund measured size");
      const dead = create($thing);
      recycle(dead);
      who.owned_objects = {dead};
      $quota_utils:summarize_one_user(who)[1] == 0 || raise(E_INVARG, "stale ownership entry counted");
      who:editor_access($quota_utils, "summarize_one_user", other) == E_PERM ||
        raise(E_INVARG, "foreign player triggered privileged accounting");
    finally
      valid(item) && $recycler:_recycle(item);
    endtry
    return true;
  endmethod

  method test_quota_schedule owner: #2
    "Repeated scheduling returns the same worker and ordinary callers cannot schedule it.";
    this.test_programmer:editor_access($quota_utils, "schedule_measurement_task") == E_PERM ||
      raise(E_INVARG, "ordinary player scheduled measurements");
    const worker = $quota_utils:schedule_measurement_task();
    try
      typeof(worker) == TYPE_INT || raise(E_INVARG, "no measurement worker");
      $quota_utils:schedule_measurement_task() == worker || raise(E_INVARG, "duplicate worker");
      $quota_utils:measurement_task_body(0) == {0, 0} || raise(E_INVARG, "zero time budget did work");
      $quota_utils:measurement_task_body(-1) == E_INVARG || raise(E_INVARG, "negative time budget accepted");
    finally
      kill_task(worker);
      $quota_utils.measurement_task_running = false;
    endtry
    return true;
  endmethod
  method test_retained_helpers owner: #2
    "Exercise error shims, pronouns, lock parsing, matrix arithmetic, and note permissions.";
    const quota_error = "E_QUOTA";
    const movement_error = "E_RECMOVE";
    `$error:(quota_error)() ! E_QUOTA' == E_QUOTA || raise(E_INVARG, "quota error helper did not raise");
    `$error:(movement_error)() ! E_RECMOVE' == E_RECMOVE || raise(E_INVARG, "movement error helper did not raise");
    const note = $recycler:_create($note);
    try
      $gender_utils:add(note);
      add_property(note, "gender", "plural", {#2, "rc"});
      $gender_utils:set(note, "plural") == "plural" || raise(E_INVARG, "pronoun update failed");
      $gender_utils:get_pronoun("s", note) == "they" || raise(E_INVARG, "pronoun lookup failed");
      $gender_utils:get_conjugation("is/are", note) == "are" || raise(E_INVARG, "plural conjugation failed");
      $gender_utils:get_conjugation("", note) == "" || raise(E_INVARG, "empty verb failed");
      note:set_text({"one", "two"});
      note:text() == {"one", "two"} || raise(E_INVARG, "note roundtrip failed");
      note:is_writable_by(this.test_player) == false || raise(E_INVARG, "foreign player may write note");
      const key = $lock_utils:parse_keyexp("me & !here", this.test_player);
      $lock_utils:eval_key(key, this.test_player) || raise(E_INVARG, "parsed lock rejected its player");
      !$lock_utils:eval_key(key, this.test_programmer) || raise(E_INVARG, "parsed lock accepted another player");
      $matrix_utils:matrix_mul({{1, 2}, {3, 4}}, {{1, 0}, {0, 1}}) == {{1, 2}, {3, 4}} ||
        raise(E_INVARG, "matrix multiplication changed");
      $generic_help:columnize("one", "two") == {"one", "two"} || raise(E_INVARG, "help names wrapped");
    finally
      $recycler:_recycle(note);
    endtry
    return true;
  endmethod
  method test_index_pruning owner: #2
    "Prune actual map keys, retaining active players and explanatory registration records.";
    const who = this.test_player;
    const sites = $site_db.sites;
    const registrations = $registration_db.registrations;
    const places = who.all_connect_places;
    const dead = create($thing);
    recycle(dead);
    try
      who.all_connect_places = {"9.example.invalid"};
      $site_db:insert("9.example.invalid", {dead, who});
      $site_db:prune_alpha();
      $site_db:find_exact("9.example.invalid") == {who} || raise(E_INVARG, "site pruning skipped an existing key");
      $registration_db:insert("+retired@example.invalid", {{dead, "zapped due to inactivity"}});
      $registration_db:insert("+audit@example.invalid", {{dead, "retain for administrator review"}});
      $registration_db:prune();
      $registration_db:find_exact("+retired@example.invalid") == $failed_match || raise(E_INVARG, "registration key was skipped");
      $registration_db:find_exact("+audit@example.invalid") == {{dead, "retain for administrator review"}} || raise(E_INVARG, "administrative reason removed");
      `this.test_programmer:editor_access($registration_db, "prune_reset") ! E_PERM' == E_PERM || raise(E_INVARG, "ordinary caller reset pruning");
    finally
      $site_db.sites = sites;
      $registration_db.registrations = registrations;
      who.all_connect_places = places;
    endtry
    return true;
  endmethod
  method test_connection_output_without_session owner: #2
    "Headless local output has no broadcast fallback; unrelated callers cannot choose a player's connection.";
    const recipient = this.test_player;
    recipient:tell_current("Do not broadcast a missing current connection.") == false || raise(E_INVARG);
    recipient:tell_current_lines({"Nor a list of lines."}) == false || raise(E_INVARG);
    set_task_perms(this.test_programmer);
    const denied = `recipient:tell_connection(#-1000, "Do not deliver.") ! E_PERM';
    denied == E_PERM || raise(E_INVARG, "Unauthorized connection output was accepted.");
    return true;
  endmethod
endobject
