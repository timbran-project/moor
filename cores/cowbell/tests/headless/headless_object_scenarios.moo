object HEADLESS_OBJECT_SCENARIOS
  name: "Headless Object Runtime Scenarios"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Headless runtime scenarios for object creation, mutation, movement, and object identity.";
  override import_export_hierarchy = {"tests", "headless"};
  override import_export_id = "headless_object_scenarios";

  verb test_headless_object_lifecycle (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: persistent object creation, mutation, movement, and destruction work without player I/O.";
    room = #-1;
    item = #-1;
    try
      room = $room:create();
      item = $thing:create();
      room:set_name_aliases("headless test room", {"headless-room"});
      item:set_name_aliases("headless test token", {"headless-token"});
      item:set_description("A {n} marker for headless runtime tests.");
      $test_utils:assert_true(valid(room), "created room should be valid");
      $test_utils:assert_true(valid(item), "created item should be valid");
      $test_utils:assert_eq(parent(room), $room, "created room should inherit from $room");
      $test_utils:assert_eq(parent(item), $thing, "created item should inherit from $thing");
      $test_utils:assert_eq(item:name(), "headless test token", "set_name_aliases should update name");
      $test_utils:assert_eq(item:aliases(), {"headless-token"}, "set_name_aliases should update aliases");
      $test_utils:assert_type(item.description, TYPE_LIST, "tokenized description should compile to sub content");
      item:moveto(room);
      $test_utils:assert_eq(item.location, room, "moveto should update item location");
      $test_utils:assert_true(item in room:contents(), "moveto should update destination contents");
      item:destroy();
      $test_utils:assert_false(valid(item), "destroy should recycle item");
      item = #-1;
      room:destroy();
      $test_utils:assert_false(valid(room), "destroy should recycle room");
      room = #-1;
    finally
      valid(item) && item:destroy();
      valid(room) && room:destroy();
    endtry
    return true;
  endverb

  verb test_headless_anonymous_object_identity (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: anonymous fixture creation produces valid anonymous objects while numbered creation does not.";
    anon = $thing:create(true);
    numbered = #-1;
    try
      numbered = $thing:create(0);
      $test_utils:assert_true(valid(anon), "anonymous fixture should be valid");
      $test_utils:assert_true(is_anonymous(anon), "anonymous fixture should report anonymous");
      $test_utils:assert_true(valid(numbered), "numbered fixture should be valid");
      $test_utils:assert_false(is_anonymous(numbered), "numbered fixture should not report anonymous");
      $test_utils:assert_eq(parent(anon), $thing, "anonymous fixture should inherit from $thing");
      $test_utils:assert_eq(parent(numbered), $thing, "numbered fixture should inherit from $thing");
    finally
      valid(numbered) && numbered:destroy();
    endtry
    return true;
  endverb
endobject
