object REACTION [
  import_export_id -> "reaction",
  import_export_hierarchy -> {"rules"}
]
  name: "Reaction Prototype"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: HACKER
  fertile: true
  readable: true

  property comparison_ops (owner: HACKER, flags: "rc") = {'eq, 'ne, 'gt, 'lt, 'ge, 'le};
  property effect_types (owner: HACKER, flags: "rc") = {
    'set,
    'increment,
    'decrement,
    'announce,
    'emote,
    'tell,
    'move,
    'trigger,
    'delay,
    'action
  };
  property event_triggers (owner: HACKER, flags: "rc") = {
    'on_get,
    'on_drop,
    'on_take,
    'on_put,
    'on_open,
    'on_close,
    'on_lock,
    'on_unlock,
    'on_enter,
    'on_leave,
    'on_pet,
    'on_wear,
    'on_remove,
    'on_use,
    'on_sit,
    'on_stand,
    'on_sittable_squeeze,
    'on_sittable_dump
  };

  override description = "Flyweight delegate for reactive behaviors on objects.";
  override object_documentation = {
    "# $reaction - Reactive Behavior System",
    "",
    "## Overview",
    "",
    "The Reaction System provides a declarative way to define dynamic behaviors on objects in response",
    "to various events. Instead of writing complex imperative verb code, builders can specify high-level",
    "triggers, conditions, and effects. This system is designed to simplify common interaction patterns,",
    "access controls, and environmental responses.",
    "",
    "Reactions are essentially encapsulated rules that execute specific actions when their criteria are met.",
    "They are particularly useful for creating:",
    "- **Interactive objects**: Doors that unlock, containers that react to items.",
    "- **Environmental responses**: Objects changing state based on player actions.",
    "- **Simple AI behaviors**: NPCs reacting to stimuli.",
    "",
    "## How It Works",
    "",
    "Each reaction is composed of three main parts:",
    "1.  **Trigger**: The event that initiates the reaction check. This can be a simple symbolic event (e.g., `'on_unlock`, `'on_pet`) or a more complex threshold condition.",
    "2.  **When Clause (Condition)**: An optional logical expression, evaluated by the `$rule_engine`, that must be true for the reaction's effects to fire. This allows for conditional behaviors (e.g., 'only if locked', 'only if owner').",
    "3.  **Effects**: A list of actions to perform if the trigger fires and the 'when' clause is satisfied. These effects range from setting properties to sending messages or triggering other events.",
    "",
    "## Creating Reactions",
    "",
    "Reactions are created using the `mk` verb on `$reaction`. It returns a flyweight that can be assigned to an object's `reactions` property.",
    "",
    "### Basic Event Trigger",
    "",
    "A reaction that fires on a simple event, with no special conditions:",
    "```moo",
    "reaction = $reaction:mk('on_unlock, 0, {",
    "  {'announce, \"{nc} hears a click from {i}.\"},",
    "  {'set, 'locked, false}",
    "});",
    "```",
    "",
    "Here:",
    "- `'on_unlock`: The symbolic event that triggers this reaction.",
    "- `0`: No 'when' clause (always fires if triggered).",
    "- `{{'announce, ...}, {'set, ...}}`: A list of effects to execute.",
    "",
    "### Reaction with a Condition (`when` clause)",
    "",
    "Conditions use the `$rule_engine` syntax to define prerequisites for effects to run:",
    "```moo",
    "reaction = $reaction:mk('on_pet, \"NOT This is_grouchy?\", {",
    "  {'increment, 'pets_received},",
    "  {'emote, \"purrs contentedly.\"}",
    "});",
    "```",
    "",
    "This reaction will only fire if the `on_pet` event occurs *and* the object (`This`) is *not* `is_grouchy?`.",
    "",
    "### Threshold Triggers",
    "",
    "Threshold triggers allow reactions to fire when an object's property crosses a specific value, rather than on a discrete event. The trigger is specified as a list:",
    "```moo",
    "reaction = $reaction:mk({'when, 'pets_received, 'ge, 10}, 0, {",
    "  {'set, 'mood, \"happy\"},",
    "  {'emote, \"seems to have warmed up.\"}",
    "});",
    "```",
    "",
    "This reaction fires when `pets_received` becomes greater than or equal to `10`. The possible comparison operators are (`'eq`, `'ne`, `'gt`, `'lt`, `'ge`, `'le`).",
    "",
    "## Effect Types",
    "",
    "The reaction system supports a variety of built-in effects. Messages within `announce`, `emote`, and `tell` effects can use `$sub_utils` templating.",
    "",
    "| Effect Type   | Syntax                               | Description                                                                  |",
    "|---------------|--------------------------------------|------------------------------------------------------------------------------|",
    "| `'set`         | `{'set, 'prop_name, value}`          | Sets a property `prop_name` on the reacting object to `value`.               |",
    "| `'increment`   | `{'increment, 'prop_name, ?amount}` | Adds `amount` (default 1) to a numeric property `prop_name`.                 |",
    "| `'decrement`   | `{'decrement, 'prop_name, ?amount}` | Subtracts `amount` (default 1) from a numeric property `prop_name`.          |",
    "| `'announce`    | `{'announce, \"message template\"}`   | Sends a message to the reacting object's location, parsed by `$sub_utils`.   |",
    "| `'emote`       | `{'emote, \"message template\"}`      | Causes the reacting object to emote in its location, parsed by `$sub_utils`. |",
    "| `'tell`        | `{'tell, 'RecipientVar, \"message\"}` | Sends a private message to a recipient (resolved from context), parsed by `$sub_utils`. |",
    "| `'move`        | `{'move, destination}`                | Moves the reacting object to the `destination` object.                       |",
    "| `'trigger`     | `{'trigger, target_obj, 'event_sym}` | Fires another symbolic event on `target_obj`.                                |",
    "| `'delay`       | `{'delay, seconds, inner_effect}`     | Schedules `inner_effect` to execute after `seconds` using `$scheduler`.      |",
    "| `'action`      | `{'action, 'verb_name, target}`       | Calls `target:action_<verb_name>(this, context)` for extensible behaviors.   |",
    "",
    "## Action Effects",
    "",
    "The `'action` effect provides an extensible way to invoke behaviors on other objects. When executed:",
    "",
    "1. The `target` is resolved (if a symbol, looked up in context; otherwise used directly)",
    "2. The verb `action_<verb_name>` is called on the target with `(reacting_object, context)`",
    "",
    "This allows objects to define their own action handlers. For example, `$sittable` defines:",
    "",
    "- `action_sit(who, context)` - makes `who` sit on the furniture",
    "- `action_stand(who, context)` - makes `who` stand up from the furniture",
    "",
    "Example reaction making Henri sit on a couch when the cupboard opens:",
    "",
    "```moo",
    "henri.sit_reaction = $reaction:mk('on_cupboard_open, 0, {{'action, 'sit, some_couch}});",
    "```",
    "",
    "Or with a context variable:",
    "",
    "```moo",
    "henri.sit_reaction = $reaction:mk('on_cupboard_open, 0, {{'action, 'sit, 'Furniture}});",
    "// Fire with: henri:fire_trigger('on_cupboard_open, ['Furniture -> some_couch])",
    "```",
    "",
    "## Message Templates",
    "",
    "As noted above, `announce`, `emote`, and `tell` effects leverage the `$sub_utils` template language for dynamic message generation. This allows messages to include information about the actor, direct/indirect objects, pronouns, and even self-alternating phrases.",
    "",
    "Examples of `$sub_utils` tokens:",
    "- `{nc}`: Capitalized name of the actor.",
    "- `{d}`: Name of the direct object.",
    "- `{i}`: Name of the indirect object (often the reacting object itself).",
    "- `{s}`: Subject pronoun for the actor (e.g., \"he\", \"she\", \"they\").",
    "- `{feel|feels}`: A self-alternating phrase that displays differently to the actor versus others.",
    "",
    "For full details on template syntax, see `$sub_utils` documentation.",
    "",
    "## Adding Reactions to Objects",
    "",
    "Reactions are stored as properties ending with `_reaction`. Use `@add-reaction` or set properties directly:",
    "",
    "```moo",
    "chest.unlock_reaction = $reaction:mk('on_unlock, 0, {{'announce, \"Click!\"}});",
    "chest.open_reaction = $reaction:mk('on_open, 0, {{'emote, \"creaks open.\"}});",
    "```",
    "",
    "Reactions are active as long as their `enabled` flag is true. Use `@enable-reaction` and `@disable-reaction` to toggle them.",
    "",
    "## Message Property References",
    "",
    "Instead of inline message strings, effects can reference message properties by symbol:",
    "",
    "```moo",
    "cat.pet_reaction = $reaction:mk('on_pet, 0, {{'emote, 'pet_msg}});",
    "cat.pet_msg = $sub_utils:compile(\"purrs contentedly.\");",
    "```",
    "",
    "If the property is a `$msg_bag`, a random message is picked each time. This allows varying responses:",
    "",
    "```moo",
    "cat.pet_msgs = $msg_bag:create(true);",
    "cat.pet_msgs:add($sub_utils:compile(\"purrs contentedly.\"));",
    "cat.pet_msgs:add($sub_utils:compile(\"rubs against {p} legs.\"));",
    "cat.pet_reaction = $reaction:mk('on_pet, 0, {{'emote, 'pet_msgs}});",
    "```"
  };

  method mk owner: HACKER
    "Create an enabled reaction flyweight from a trigger, optional when clause, and effect specs.";
    "Args: trigger, when_clause (0 or rule string), effects (list of effect specs)";
    "Returns: <REACTION, .trigger, .when, .effects, .enabled, .fired_at>.";
    {trigger, ?when_clause = 0, ?effects = {}} = args;
    "Validate trigger";
    this:validate_trigger(trigger);
    "Parse when clause if provided";
    parsed_when = 0;
    if (when_clause && typeof(when_clause) == TYPE_STR)
      parsed_when = $rule_engine:parse_expression(when_clause);
    endif
    "Parse and validate effects";
    parsed_effects = {};
    for effect_spec in (effects)
      parsed_effects = {@parsed_effects, this:parse_effect(effect_spec)};
    endfor
    return <this, .trigger = trigger, .when = parsed_when, .effects = parsed_effects, .enabled = true, .fired_at = 0>;
  endmethod

  method validate_trigger owner: HACKER
    "Validate an event-symbol trigger or threshold trigger list.";
    "Threshold form is {'when, property_symbol, comparison_op, threshold_value}.";
    {trigger} = args;
    "Event trigger - just a symbol";
    if (typeof(trigger) == TYPE_SYM)
      return true;
    endif
    "Threshold trigger - {'when, 'prop, 'op, value}";
    if (typeof(trigger) == TYPE_LIST)
      length(trigger) == 4 || raise(E_INVARG, "Threshold trigger must be {'when, 'prop, 'op, value}");
      {kind, prop, op, value} = trigger;
      kind == 'when || raise(E_INVARG, "Threshold trigger must start with 'when");
      typeof(prop) == TYPE_SYM || raise(E_INVARG, "Property must be symbol");
      op in this.comparison_ops || raise(E_INVARG, "Invalid comparison operator: " + tostr(op));
      return true;
    endif
    raise(E_INVARG, "Trigger must be symbol or {'when, 'prop, 'op, value}");
  endmethod

  method parse_effect owner: HACKER
    "Parse one effect spec into a validated reaction-effect flyweight.";
    "String message effects are compiled through $sub_utils; list messages are preserved.";
    {spec} = args;
    typeof(spec) == TYPE_LIST || raise(E_INVARG, "Effect must be list");
    length(spec) >= 2 || raise(E_INVARG, "Effect must have at least type and one argument");
    effect_type = spec[1];
    effect_type in this.effect_types || raise(E_INVARG, "Unknown effect type: " + tostr(effect_type));
    if (effect_type == 'set)
      length(spec) == 3 || raise(E_INVARG, "'set requires {'set, 'prop, value}");
      {_, prop, value} = spec;
      return <$reaction, .type = 'set, .prop = prop, .value = value>;
    elseif (effect_type == 'increment)
      {_, prop, ?by = 1} = spec;
      return <$reaction, .type = 'increment, .prop = prop, .by = by>;
    elseif (effect_type == 'decrement)
      {_, prop, ?by = 1} = spec;
      return <$reaction, .type = 'decrement, .prop = prop, .by = by>;
    elseif (effect_type == 'announce)
      {_, msg} = spec;
      compiled_msg = typeof(msg) == TYPE_STR ? $sub_utils:compile(msg) | msg;
      return <$reaction, .type = 'announce, .msg = compiled_msg>;
    elseif (effect_type == 'emote)
      {_, msg} = spec;
      compiled_msg = typeof(msg) == TYPE_STR ? $sub_utils:compile(msg) | msg;
      return <$reaction, .type = 'emote, .msg = compiled_msg>;
    elseif (effect_type == 'tell)
      {_, target_var, msg} = spec;
      compiled_msg = typeof(msg) == TYPE_STR ? $sub_utils:compile(msg) | msg;
      return <$reaction, .type = 'tell, .target = target_var, .msg = compiled_msg>;
    elseif (effect_type == 'move)
      {_, dest} = spec;
      return <$reaction, .type = 'move, .destination = dest>;
    elseif (effect_type == 'trigger)
      {_, target_obj, event} = spec;
      return <$reaction, .type = 'trigger, .target = target_obj, .event = event>;
    elseif (effect_type == 'delay)
      {_, seconds, inner_effect} = spec;
      parsed_inner = this:parse_effect(inner_effect);
      return <$reaction, .type = 'delay, .seconds = seconds, .effect = parsed_inner>;
    elseif (effect_type == 'action)
      {_, action_name, ?action_target = 0} = spec;
      typeof(action_name) == TYPE_SYM || raise(E_INVARG, "'action requires symbol for action name");
      return <$reaction, .type = 'action, .action = action_name, .action_target = action_target>;
    endif
    raise(E_INVARG, "Unhandled effect type: " + tostr(effect_type));
  endmethod

  method compare owner: HACKER
    "Compare two values using one of the configured comparison operator symbols.";
    {left, op, right} = args;
    if (op == 'eq)
      return left == right;
    elseif (op == 'ne)
      return left != right;
    elseif (op == 'gt)
      return left > right;
    elseif (op == 'lt)
      return left < right;
    elseif (op == 'ge)
      return left >= right;
    elseif (op == 'le)
      return left <= right;
    endif
    return false;
  endmethod

  method threshold_crossed owner: HACKER
    "Return true when a value transition newly satisfies a threshold comparison.";
    {old_value, new_value, op, threshold} = args;
    was_met = this:compare(old_value, op, threshold);
    now_met = this:compare(new_value, op, threshold);
    return now_met && !was_met;
  endmethod

  method execute owner: HACKER
    "Execute this reaction in the given context if its when clause succeeds.";
    "Context is map: ['Actor -> player, 'This -> object, 'Key -> iobj, ...]";
    "Returns false when a when clause fails, otherwise true after all effects run.";
    {context} = args;
    "Check when clause if present (flyweights are falsy, so check != 0)";
    if (this.when != 0)
      result = $rule_engine:evaluate(this.when, context);
      if (!result['success])
        return false;
      endif
      "Merge any new bindings into context";
      if (maphaskey(result, 'bindings))
        for key in (mapkeys(result['bindings]))
          context[key] = result['bindings][key];
        endfor
      endif
    endif
    "Execute each effect";
    target = context['This];
    for effect in (this.effects)
      this:execute_effect(effect, context, target);
    endfor
    return true;
  endmethod

  method _resolve_msg owner: HACKER
    "Resolve a message reference to a compiled template list.";
    "If msg is a symbol, looks up that property on target.";
    "If the property is a $msg_bag (object or flyweight), picks randomly.";
    "Returns a list suitable for @-splat into $event:mk_info.";
    {msg, target} = args;
    "If it's a symbol, look up the property on target";
    if (typeof(msg) == TYPE_SYM)
      prop_name = tostr(msg);
      prop_value = `target.(prop_name) ! E_PROPNF => 0';
      prop_value == 0 && return {"(missing message: " + prop_name + ")"};
      "If it's a msg_bag (object or flyweight), pick randomly";
      if (typeof(prop_value) == TYPE_OBJ && isa(prop_value, $msg_bag))
        return prop_value:pick();
      elseif (typeof(prop_value) == TYPE_FLYWEIGHT && prop_value.delegate == $msg_bag)
        return prop_value:pick();
      endif
      "Otherwise use the property value directly (should be compiled list)";
      return prop_value;
    endif
    "Already a compiled list or other value";
    return msg;
  endmethod

  method execute_effect owner: HACKER
    "Execute a single parsed or raw effect against target using context bindings.";
    "Mutation effects also check threshold reactions on the same target.";
    {effect, context, target} = args;
    "Parse list effects on the fly for convenience";
    if (typeof(effect) == TYPE_LIST)
      effect = this:parse_effect(effect);
    endif
    actor = context['Actor] || player;
    if (effect.type == 'set)
      old_value = `target.(effect.prop) ! E_PROPNF => 0';
      target.(effect.prop) = effect.value;
      target:_check_thresholds(effect.prop, old_value, effect.value, context);
    elseif (effect.type == 'increment)
      old_value = `target.(effect.prop) ! E_PROPNF => 0';
      new_value = old_value + effect.by;
      target.(effect.prop) = new_value;
      target:_check_thresholds(effect.prop, old_value, new_value, context);
    elseif (effect.type == 'decrement)
      old_value = `target.(effect.prop) ! E_PROPNF => 0';
      new_value = old_value - effect.by;
      target.(effect.prop) = new_value;
      target:_check_thresholds(effect.prop, old_value, new_value, context);
    elseif (effect.type == 'announce)
      "Announce to actor's room - actor is the player, dobj is the reacting object";
      msg = this:_resolve_msg(effect.msg, target);
      event = $event:mk_info(actor, @msg):with_dobj(target);
      room = isa(actor, $player) ? actor.location | target.location;
      if (valid(room) && isa(room, $room))
        room:announce(event);
      endif
    elseif (effect.type == 'emote)
      "Object 'does' something - auto-prefix target name like emote command";
      msg = this:_resolve_msg(effect.msg, target);
      event = $event:mk_emote(target, target.name, " ", @msg):with_dobj(actor);
      room = isa(actor, $player) ? actor.location | target.location;
      if (valid(room) && isa(room, $room))
        room:announce(event);
      endif
    elseif (effect.type == 'tell)
      "Private message to a specific target";
      recipient = context[effect.target];
      if (valid(recipient))
        msg = this:_resolve_msg(effect.msg, target);
        event = $event:mk_info(actor, @msg):with_iobj(target);
        recipient:inform_current(event);
      endif
    elseif (effect.type == 'move)
      dest = typeof(effect.destination) == TYPE_SYM ? context[effect.destination] | effect.destination;
      if (valid(dest))
        move(target, dest);
      endif
    elseif (effect.type == 'trigger)
      "Fire another trigger on another object";
      if (valid(effect.target))
        effect.target:fire_trigger(effect.event, context);
      endif
    elseif (effect.type == 'delay)
      "Schedule future effect via scheduler";
      fork (effect.seconds)
        this:execute_effect(effect.effect, context, target);
      endfork
    elseif (effect.type == 'action)
      "Call action_<name> on action_target, passing the reacting object and context";
      action_target = effect.action_target;
      if (typeof(action_target) == TYPE_SYM)
        action_target = context[action_target];
      endif
      if (valid(action_target))
        verb_name = "action_" + tostr(effect.action);
        `action_target:(verb_name)(target, context) ! E_VERBNF';
      endif
    endif
  endmethod

  method test_mk_event_trigger owner: HACKER
    "Test creating a reaction with a simple event trigger.";
    reaction = this:mk('on_unlock, 0, {});
    $test_utils:assert_type(reaction, TYPE_FLYWEIGHT, "mk() should return a flyweight");
    $test_utils:assert_eq(reaction.delegate, this, "delegate should be $reaction");
    $test_utils:assert_eq(reaction.trigger, 'on_unlock, "trigger should be stored");
    $test_utils:assert_eq(reaction.when, 0, "default when clause should be disabled");
    $test_utils:assert_eq(reaction.effects, {}, "empty effects should be preserved");
    $test_utils:assert_true(reaction.enabled, "reactions should be enabled by default");
    return true;
  endmethod

  method test_mk_threshold_trigger owner: HACKER
    "Test creating a reaction with a threshold trigger.";
    reaction = this:mk({'when, 'pets_received, 'ge, 10}, 0, {});
    $test_utils:assert_type(reaction, TYPE_FLYWEIGHT, "mk() should return a flyweight");
    $test_utils:assert_type(reaction.trigger, TYPE_LIST, "threshold trigger should be a list");
    $test_utils:assert_eq(reaction.trigger[1], 'when, "threshold trigger kind");
    $test_utils:assert_eq(reaction.trigger[2], 'pets_received, "threshold trigger property");
    $test_utils:assert_eq(reaction.trigger[3], 'ge, "threshold trigger operator");
    $test_utils:assert_eq(reaction.trigger[4], 10, "threshold trigger value");
    return true;
  endmethod

  method test_mk_with_condition owner: HACKER
    "Test creating a reaction with a when condition.";
    reaction = this:mk('on_pet, "NOT This is_grouchy?", {});
    $test_utils:assert_type(reaction, TYPE_FLYWEIGHT, "mk() should return a flyweight");
    $test_utils:assert_true(reaction.when != 0, "string when clause should be parsed");
    $test_utils:assert_type(reaction.when, TYPE_FLYWEIGHT, "when clause should be a rule flyweight");
    return true;
  endmethod

  method test_mk_invalid_trigger owner: HACKER
    "Test that invalid triggers raise errors.";
    $test_utils:assert_raises(E_INVARG, this, "mk", {"not_a_symbol", 0, {}}, "string triggers should be rejected");
    $test_utils:assert_raises(E_INVARG, this, "mk", {{'wrong, 'prop}, 0, {}}, "malformed threshold triggers should be rejected");
    return true;
  endmethod

  method test_parse_effect_set owner: HACKER
    "Test parsing a 'set' effect.";
    effect = this:parse_effect({'set, 'locked, false});
    $test_utils:assert_type(effect, TYPE_FLYWEIGHT, "parse_effect() should return a flyweight");
    $test_utils:assert_eq(effect.type, 'set, "effect type");
    $test_utils:assert_eq(effect.prop, 'locked, "set property");
    $test_utils:assert_false(effect.value, "set value");
    return true;
  endmethod

  method test_parse_effect_increment owner: HACKER
    "Test parsing an 'increment' effect.";
    effect = this:parse_effect({'increment, 'counter});
    $test_utils:assert_type(effect, TYPE_FLYWEIGHT, "parse_effect() should return a flyweight");
    $test_utils:assert_eq(effect.type, 'increment, "effect type");
    $test_utils:assert_eq(effect.prop, 'counter, "increment property");
    $test_utils:assert_eq(effect.by, 1, "default increment amount");
    effect2 = this:parse_effect({'increment, 'counter, 5});
    $test_utils:assert_eq(effect2.by, 5, "explicit increment amount");
    return true;
  endmethod

  method test_parse_effect_announce owner: HACKER
    "Test parsing an 'announce' effect with template compilation.";
    effect = this:parse_effect({'announce, "{nc} hears a click."});
    $test_utils:assert_type(effect, TYPE_FLYWEIGHT, "parse_effect() should return a flyweight");
    $test_utils:assert_eq(effect.type, 'announce, "effect type");
    $test_utils:assert_type(effect.msg, TYPE_LIST, "string messages should compile to template lists");
    $test_utils:assert_true(length(effect.msg) > 0, "compiled message should have content");
    return true;
  endmethod

  method test_parse_effect_emote owner: HACKER
    "Test parsing an 'emote' effect.";
    effect = this:parse_effect({'emote, "purrs contentedly."});
    $test_utils:assert_type(effect, TYPE_FLYWEIGHT, "parse_effect() should return a flyweight");
    $test_utils:assert_eq(effect.type, 'emote, "effect type");
    $test_utils:assert_type(effect.msg, TYPE_LIST, "string messages should compile to template lists");
    return true;
  endmethod

  method test_parse_effect_trigger owner: HACKER
    "Test parsing a 'trigger' effect.";
    effect = this:parse_effect({'trigger, $root, 'on_activate});
    $test_utils:assert_type(effect, TYPE_FLYWEIGHT, "parse_effect() should return a flyweight");
    $test_utils:assert_eq(effect.type, 'trigger, "effect type");
    $test_utils:assert_eq(effect.target, $root, "trigger target");
    $test_utils:assert_eq(effect.event, 'on_activate, "trigger event");
    return true;
  endmethod

  method test_parse_effect_delay owner: HACKER
    "Test parsing a 'delay' effect with nested effect.";
    effect = this:parse_effect({'delay, 5, {'announce, "Boom!"}});
    $test_utils:assert_type(effect, TYPE_FLYWEIGHT, "parse_effect() should return a flyweight");
    $test_utils:assert_eq(effect.type, 'delay, "effect type");
    $test_utils:assert_eq(effect.seconds, 5, "delay seconds");
    $test_utils:assert_type(effect.effect, TYPE_FLYWEIGHT, "nested effect should be parsed");
    $test_utils:assert_eq(effect.effect.type, 'announce, "nested effect type");
    return true;
  endmethod

  method test_parse_effect_invalid owner: HACKER
    "Test that invalid effects raise errors.";
    $test_utils:assert_raises(E_INVARG, this, "parse_effect", {{'unknown_type, "foo"}}, "unknown effect type should be rejected");
    $test_utils:assert_raises(E_INVARG, this, "parse_effect", {"not a list"}, "non-list effect should be rejected");
    return true;
  endmethod

  method test_mk_compiles_effects owner: HACKER
    "Test that mk() parses all effects.";
    reaction = this:mk('on_unlock, 0, {{'announce, "Click!"}, {'set, 'locked, false}, {'increment, 'times_unlocked}});
    $test_utils:assert_eq(length(reaction.effects), 3, "mk() should parse every effect");
    $test_utils:assert_eq(reaction.effects[1].type, 'announce, "first effect type");
    $test_utils:assert_eq(reaction.effects[2].type, 'set, "second effect type");
    $test_utils:assert_eq(reaction.effects[3].type, 'increment, "third effect type");
    return true;
  endmethod

  method test_compare owner: HACKER
    "Test comparison operators.";
    $test_utils:assert_true(this:compare(5, 'eq, 5), "eq should match equal values");
    $test_utils:assert_false(this:compare(5, 'eq, 3), "eq should reject unequal values");
    $test_utils:assert_true(this:compare(5, 'ne, 3), "ne should match unequal values");
    $test_utils:assert_true(this:compare(5, 'gt, 3), "gt should compare greater values");
    $test_utils:assert_false(this:compare(3, 'gt, 5), "gt should reject smaller values");
    $test_utils:assert_true(this:compare(3, 'lt, 5), "lt should compare smaller values");
    $test_utils:assert_true(this:compare(5, 'ge, 5), "ge should accept equality");
    $test_utils:assert_true(this:compare(5, 'ge, 3), "ge should accept greater values");
    $test_utils:assert_true(this:compare(5, 'le, 5), "le should accept equality");
    $test_utils:assert_true(this:compare(3, 'le, 5), "le should accept smaller values");
    return true;
  endmethod

  method test_threshold_crossed owner: HACKER
    "Test threshold crossing detection.";
    $test_utils:assert_true(this:threshold_crossed(9, 10, 'ge, 10), "9->10 crosses >=10");
    $test_utils:assert_true(this:threshold_crossed(5, 15, 'ge, 10), "5->15 crosses >=10");
    $test_utils:assert_false(this:threshold_crossed(10, 11, 'ge, 10), "10->11 already met >=10");
    $test_utils:assert_false(this:threshold_crossed(8, 9, 'ge, 10), "8->9 does not cross >=10");
    $test_utils:assert_true(this:threshold_crossed(9, 10, 'eq, 10), "9->10 crosses ==10");
    $test_utils:assert_false(this:threshold_crossed(10, 10, 'eq, 10), "10->10 already met ==10");
    $test_utils:assert_true(this:threshold_crossed(11, 10, 'eq, 10), "11->10 crosses ==10");
    return true;
  endmethod

  method test_execute_mutation_effects_and_thresholds owner: HACKER
    "Test mutation effects and threshold reactions during execution.";
    target = $test_utils:anonymous($root);
    add_property(target, "score", 1, {this.owner, "r"});
    add_property(target, "state", "idle", {this.owner, "r"});
    add_property(target, "threshold_hit", false, {this.owner, "r"});
    threshold = this:mk({'when, 'score, 'ge, 5}, 0, {{'set, 'threshold_hit, true}});
    add_property(target, "score_threshold_reaction", threshold, {this.owner, "r"});
    reaction = this:mk('on_score, 0, {{'increment, 'score, 4}, {'decrement, 'score, 2}, {'set, 'state, "done"}});
    $test_utils:assert_true(reaction:execute(['Actor -> player, 'This -> target]), "mutation reaction should execute");
    $test_utils:assert_eq(target.score, 3, "increment and decrement effects should mutate numeric properties");
    $test_utils:assert_eq(target.state, "done", "set effect should update target property");
    $test_utils:assert_true(target.threshold_hit, "threshold reaction should fire when score crosses threshold");
    return true;
  endmethod

  method test_fire_trigger_enabled_filtering owner: HACKER
    "Test root fire_trigger dispatches matching enabled reactions only.";
    target = $test_utils:anonymous($root);
    add_property(target, "count", 0, {this.owner, "r"});
    enabled_reaction = this:mk('on_ping, 0, {{'increment, 'count, 1}});
    disabled_reaction = this:mk('on_ping, 0, {{'increment, 'count, 100}});
    disabled_reaction.enabled = false;
    add_property(target, "enabled_ping_reaction", enabled_reaction, {this.owner, "r"});
    add_property(target, "disabled_ping_reaction", disabled_reaction, {this.owner, "r"});
    target:fire_trigger('on_ping, ['Actor -> player]);
    $test_utils:assert_eq(target.count, 1, "fire_trigger should skip disabled reactions");
    return true;
  endmethod

  method test_execute_when_clause_gates_effects owner: HACKER
    "Test that when clauses block or allow reaction effects.";
    target = $test_utils:anonymous($root);
    add_property(target, "ready", false, {this.owner, "r"});
    add_property(target, "fired", false, {this.owner, "r"});
    add_verb(target, {this.owner, "rxd", "fact_ready"}, {"this", "none", "this"});
    set_verb_code(target, "fact_ready", {"return this.ready;"});
    reaction = this:mk('on_ready, "This ready?", {{'set, 'fired, true}});
    add_property(target, "ready_reaction", reaction, {this.owner, "r"});
    target:fire_trigger('on_ready, ['Actor -> player]);
    $test_utils:assert_false(target.fired, "failed when clause should block effects");
    target.ready = true;
    target:fire_trigger('on_ready, ['Actor -> player]);
    $test_utils:assert_true(target.fired, "successful when clause should allow effects");
    return true;
  endmethod

  method test_trigger_and_action_effects owner: HACKER
    "Test trigger effects chaining into action effects with context bindings.";
    source = $test_utils:anonymous($root);
    receiver = $test_utils:anonymous($root);
    handler = $test_utils:anonymous($root);
    add_property(receiver, "action_seen", false, {this.owner, "r"});
    add_property(receiver, "action_this", #-1, {this.owner, "r"});
    add_property(receiver, "action_actor", #-1, {this.owner, "r"});
    add_verb(handler, {this.owner, "rxd", "action_mark"}, {"this", "none", "this"});
    set_verb_code(handler, "action_mark", {"{target, context} = args;", "target.action_seen = true;", "target.action_this = context['This];", "target.action_actor = context['Actor];", "return true;"});
    add_property(source, "chain_reaction", this:mk('on_first, 0, {{'trigger, receiver, 'on_second}}), {this.owner, "r"});
    add_property(receiver, "mark_reaction", this:mk('on_second, 0, {{'action, 'mark, handler}}), {this.owner, "r"});
    source:fire_trigger('on_first, ['Actor -> player]);
    $test_utils:assert_true(receiver.action_seen, "triggered action should run");
    $test_utils:assert_eq(receiver.action_this, receiver, "chained trigger should update This binding");
    $test_utils:assert_eq(receiver.action_actor, player, "chained trigger should preserve Actor binding");
    return true;
  endmethod
endobject
