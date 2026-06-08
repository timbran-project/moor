object HEADLESS_EVENT_SCENARIOS
  name: "Headless Event Runtime Scenarios"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Headless runtime scenarios for pure event and substitution rendering.";
  override import_export_hierarchy = {"tests", "headless"};
  override import_export_id = "headless_event_scenarios";

  verb _fixtures (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create actor, observer, room, and item fixtures for rendering scenarios.";
    room = create($room);
    actor = create($thing);
    observer = create($thing);
    item = create($thing);
    room:set_name_aliases("headless event room", {"headless-event-room"});
    actor:set_name_aliases("headless event actor", {"headless-event-actor"});
    observer:set_name_aliases("headless event observer", {"headless-event-observer"});
    item:set_name_aliases("headless event token", {"headless-event-token"});
    actor:moveto(room);
    observer:moveto(room);
    item:moveto(room);
    return {actor, observer, room, item};
  endverb

  verb _destroy_fixtures (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Destroy valid persistent fixtures in reverse containment order.";
    {actor, observer, room, item} = args;
    valid(item) && item:destroy();
    valid(observer) && observer:destroy();
    valid(actor) && actor:destroy();
    valid(room) && room:destroy();
    return true;
  endverb

  verb test_headless_event_perspective_rendering (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: event substitution renders actor and observer perspectives without delivery.";
    actor = observer = room = item = #-1;
    try
      {actor, observer, room, item} = this:_fixtures();
      event = $event:mk_info(actor, $sub:nc(), " ", $sub:self_alt("take", "takes"), " ", $sub:the('d), " in ", $sub:l(), "."):with_dobj(item);
      $test_utils:assert_true(event:validate(), "event should validate before rendering");
      $test_utils:assert_eq(event:transform_for(actor), {"You take the headless event token in headless event room."}, "actor render should use second-person substitution");
      $test_utils:assert_eq(event:transform_for(observer), {"Headless event actor takes the headless event token in headless event room."}, "observer render should use third-person substitution");
    finally
      this:_destroy_fixtures(actor, observer, room, item);
    endtry
    return true;
  endverb

  verb test_headless_event_message_bag_template_rendering (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: message bag entries can be compiled, picked, and rendered through events.";
    actor = observer = room = item = #-1;
    try
      {actor, observer, room, item} = this:_fixtures();
      template = "{nc} {have} {the d}.";
      compiled = $sub_utils:compile(template);
      bag = $msg_bag:mk(compiled);
      $test_utils:assert_true($msg_bag:is_msg_bag(bag), "compiled flyweight should be a message bag");
      $test_utils:assert_eq($sub_utils:decompile(compiled), template, "compiled template should decompile");
      picked = bag:pick();
      event = $event:mk_info(actor, @picked):with_dobj(item);
      $test_utils:assert_eq(event:transform_for(actor), {"You have the headless event token."}, "actor render should use message bag template");
      $test_utils:assert_eq(event:transform_for(observer), {"Headless event actor has the headless event token."}, "observer render should conjugate message bag template");
    finally
      this:_destroy_fixtures(actor, observer, room, item);
    endtry
    return true;
  endverb

  verb test_headless_event_message_bag_mutation (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: message bag flyweight mutation preserves compiled template rendering.";
    actor = observer = room = item = #-1;
    try
      {actor, observer, room, item} = this:_fixtures();
      bag = $msg_bag:mk($sub_utils:compile("{nc} {look} at {the d}."));
      bag = bag:add($sub_utils:compile("{the dc} {be_dobj} here."));
      $test_utils:assert_eq(length(bag:entries()), 2, "add should append a message bag entry");
      bag = bag:set_entry(2, $sub_utils:compile("{nc} {feel|feels} ready."));
      bag = bag:remove(1);
      $test_utils:assert_eq(length(bag:entries()), 1, "remove should delete a message bag entry");
      picked = bag:pick();
      event = $event:mk_info(actor, @picked):with_dobj(item);
      $test_utils:assert_eq(event:transform_for(actor), {"You feel ready."}, "mutated message bag should render actor perspective");
      $test_utils:assert_eq(event:transform_for(observer), {"Headless event actor feels ready."}, "mutated message bag should render observer perspective");
    finally
      this:_destroy_fixtures(actor, observer, room, item);
    endtry
    return true;
  endverb
endobject
