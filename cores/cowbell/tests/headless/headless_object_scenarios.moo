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

  verb test_headless_parent_change_invariants (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: changing an object's parent updates the prototype chain and child indexes.";
    child = #-1;
    try
      child = $thing:create();
      old_parent = parent(child);
      chparent(child, $room);
      $test_utils:assert_eq(parent(child), $room, "chparent should update the object's parent");
      $test_utils:assert_true(child in children($room), "chparent should add object to new parent's children");
      $test_utils:assert_false(child in children(old_parent), "chparent should remove object from old parent's children");
    finally
      valid(child) && child:destroy();
    endtry
    return true;
  endverb

  verb test_headless_failed_moveto_preserves_containment (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: a recursive move fails without changing locations or contents.";
    room = #-1;
    box = #-1;
    item = #-1;
    try
      room = $room:create();
      box = $thing:create();
      item = $thing:create();
      box:moveto(room);
      item:moveto(box);
      result = box:moveto(item);
      $test_utils:assert_eq(result, E_RECMOVE, "recursive moveto should report E_RECMOVE");
      $test_utils:assert_eq(box.location, room, "failed moveto should leave source location unchanged");
      $test_utils:assert_eq(item.location, box, "failed moveto should leave nested item location unchanged");
      $test_utils:assert_true(box in room:contents(), "failed moveto should leave source in original container");
      $test_utils:assert_true(item in box:contents(), "failed moveto should leave nested item in source contents");
    finally
      valid(item) && item:destroy();
      valid(box) && box:destroy();
      valid(room) && room:destroy();
    endtry
    return true;
  endverb

  verb test_headless_object_permission_boundary (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: non-owner task permissions cannot mutate another object's protected metadata.";
    target = #-1;
    try
      target = $thing:create();
      target:set_description("unchanged");
      denied = false;
      try
        this:_set_raw_description_as_player(target, "changed");
      except (E_PERM)
        denied = true;
      endtry
      $test_utils:assert_true(denied, "non-owner metadata mutation should be denied");
      $test_utils:assert_eq(target.description, "unchanged", "denied metadata mutation should preserve description");
    finally
      valid(target) && target:destroy();
    endtry
    return true;
  endverb

  verb test_headless_destroy_cleans_containment (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: destroying a container detaches its contents from the recycled location.";
    room = #-1;
    item = #-1;
    try
      room = $room:create();
      item = $thing:create();
      item:moveto(room);
      $test_utils:assert_true(item in room:contents(), "fixture item should start in room contents");
      room:destroy();
      $test_utils:assert_false(valid(room), "destroyed room should be invalid");
      $test_utils:assert_true(valid(item), "destroying room should not recycle contained item");
      $test_utils:assert_eq(item.location, #-1, "destroying room should detach contained item");
      room = #-1;
      item:destroy();
      item = #-1;
    finally
      valid(item) && item:destroy();
      valid(room) && room:destroy();
    endtry
    return true;
  endverb

  verb _set_raw_description_as_player (this none this) owner: PLAYER flags: "rxd"
    "Attempt protected property mutation under non-owner player task permissions.";
    {target, description} = args;
    target.description = description;
    return true;
  endverb
endobject
