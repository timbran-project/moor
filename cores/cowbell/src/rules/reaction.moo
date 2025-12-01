object REACTION
  name: "Reaction Prototype"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: HACKER
  fertile: true
  readable: true

  override description = "Flyweight delegate for reactive behaviors on objects.";
  override import_export_hierarchy = {"rules"};
  override import_export_id = "reaction";

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

  property effect_types (owner: HACKER, flags: "rc") = {
    'set, 'increment, 'decrement,
    'announce, 'emote, 'tell,
    'move, 'trigger, 'delay
  };

  property event_triggers (owner: HACKER, flags: "rc") = {
    'on_get, 'on_drop, 'on_take, 'on_put,
    'on_open, 'on_close, 'on_lock, 'on_unlock,
    'on_enter, 'on_leave, 'on_pet,
    'on_wear, 'on_remove, 'on_use
  };

  property comparison_ops (owner: HACKER, flags: "rc") = {
    'eq, 'ne, 'gt, 'lt, 'ge, 'le
  };

  verb test_mk_event_trigger (this none this) owner: HACKER flags: "rxd"
    "Test creating a reaction with a simple event trigger.";
    reaction = this:mk('on_unlock, 0, {});

    typeof(reaction) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    reaction.delegate == this || raise(E_ASSERT, "Delegate should be $reaction");
    reaction.trigger == 'on_unlock || raise(E_ASSERT, "Trigger should be 'on_unlock");
    reaction.when == 0 || raise(E_ASSERT, "When should be 0 (no condition)");
    reaction.effects == {} || raise(E_ASSERT, "Effects should be empty list");
    reaction.enabled == true || raise(E_ASSERT, "Should be enabled by default");

    return true;
  endverb

  verb test_mk_threshold_trigger (this none this) owner: HACKER flags: "rxd"
    "Test creating a reaction with a threshold trigger.";
    reaction = this:mk({'when, 'pets_received, 'ge, 10}, 0, {});

    typeof(reaction) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    typeof(reaction.trigger) == LIST || raise(E_ASSERT, "Trigger should be list");
    reaction.trigger[1] == 'when || raise(E_ASSERT, "Trigger[1] should be 'when");
    reaction.trigger[2] == 'pets_received || raise(E_ASSERT, "Trigger[2] should be property");
    reaction.trigger[3] == 'ge || raise(E_ASSERT, "Trigger[3] should be operator");
    reaction.trigger[4] == 10 || raise(E_ASSERT, "Trigger[4] should be threshold value");

    return true;
  endverb

  verb test_mk_with_condition (this none this) owner: HACKER flags: "rxd"
    "Test creating a reaction with a when condition.";
    reaction = this:mk('on_pet, "NOT This is_grouchy?", {});

    typeof(reaction) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    reaction.when != 0 || raise(E_ASSERT, "When should be parsed rule");
    typeof(reaction.when) == FLYWEIGHT || raise(E_ASSERT, "When should be rule flyweight");

    return true;
  endverb

  verb test_mk_invalid_trigger (this none this) owner: HACKER flags: "rxd"
    "Test that invalid triggers raise errors.";
    caught = false;
    try
      this:mk("not_a_symbol", 0, {});
    except (E_INVARG)
      caught = true;
    endtry
    caught || raise(E_ASSERT, "Should reject non-symbol trigger");

    caught = false;
    try
      this:mk({'wrong, 'prop}, 0, {});
    except (E_INVARG)
      caught = true;
    endtry
    caught || raise(E_ASSERT, "Should reject malformed threshold trigger");

    return true;
  endverb

  verb test_parse_effect_set (this none this) owner: HACKER flags: "rxd"
    "Test parsing a 'set' effect.";
    effect = this:parse_effect({'set, 'locked, false});

    typeof(effect) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    effect.type == 'set || raise(E_ASSERT, "Type should be 'set");
    effect.prop == 'locked || raise(E_ASSERT, "Prop should be 'locked");
    effect.value == false || raise(E_ASSERT, "Value should be false");

    return true;
  endverb

  verb test_parse_effect_increment (this none this) owner: HACKER flags: "rxd"
    "Test parsing an 'increment' effect.";
    effect = this:parse_effect({'increment, 'counter});

    typeof(effect) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    effect.type == 'increment || raise(E_ASSERT, "Type should be 'increment");
    effect.prop == 'counter || raise(E_ASSERT, "Prop should be 'counter");
    effect.by == 1 || raise(E_ASSERT, "Default increment should be 1");

    "Test with explicit amount";
    effect2 = this:parse_effect({'increment, 'counter, 5});
    effect2.by == 5 || raise(E_ASSERT, "Explicit increment should be 5");

    return true;
  endverb

  verb test_parse_effect_announce (this none this) owner: HACKER flags: "rxd"
    "Test parsing an 'announce' effect with template compilation.";
    effect = this:parse_effect({'announce, "{nc} hears a click."});

    typeof(effect) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    effect.type == 'announce || raise(E_ASSERT, "Type should be 'announce");
    typeof(effect.msg) == LIST || raise(E_ASSERT, "Msg should be compiled to list");
    length(effect.msg) > 0 || raise(E_ASSERT, "Msg should have content");

    return true;
  endverb

  verb test_parse_effect_emote (this none this) owner: HACKER flags: "rxd"
    "Test parsing an 'emote' effect.";
    effect = this:parse_effect({'emote, "purrs contentedly."});

    typeof(effect) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    effect.type == 'emote || raise(E_ASSERT, "Type should be 'emote");
    typeof(effect.msg) == LIST || raise(E_ASSERT, "Msg should be compiled to list");

    return true;
  endverb

  verb test_parse_effect_trigger (this none this) owner: HACKER flags: "rxd"
    "Test parsing a 'trigger' effect.";
    effect = this:parse_effect({'trigger, $root, 'on_activate});

    typeof(effect) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    effect.type == 'trigger || raise(E_ASSERT, "Type should be 'trigger");
    effect.target == $root || raise(E_ASSERT, "Target should be $root");
    effect.event == 'on_activate || raise(E_ASSERT, "Event should be 'on_activate");

    return true;
  endverb

  verb test_parse_effect_delay (this none this) owner: HACKER flags: "rxd"
    "Test parsing a 'delay' effect with nested effect.";
    effect = this:parse_effect({'delay, 5, {'announce, "Boom!"}});

    typeof(effect) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    effect.type == 'delay || raise(E_ASSERT, "Type should be 'delay");
    effect.seconds == 5 || raise(E_ASSERT, "Seconds should be 5");
    typeof(effect.effect) == FLYWEIGHT || raise(E_ASSERT, "Nested effect should be flyweight");
    effect.effect.type == 'announce || raise(E_ASSERT, "Nested effect should be announce");

    return true;
  endverb

  verb test_parse_effect_invalid (this none this) owner: HACKER flags: "rxd"
    "Test that invalid effects raise errors.";
    caught = false;
    try
      this:parse_effect({'unknown_type, "foo"});
    except (E_INVARG)
      caught = true;
    endtry
    caught || raise(E_ASSERT, "Should reject unknown effect type");

    caught = false;
    try
      this:parse_effect("not a list");
    except (E_INVARG)
      caught = true;
    endtry
    caught || raise(E_ASSERT, "Should reject non-list effect");

    return true;
  endverb

  verb test_mk_compiles_effects (this none this) owner: HACKER flags: "rxd"
    "Test that mk() parses all effects.";
    reaction = this:mk('on_unlock, 0, {
      {'announce, "Click!"},
      {'set, 'locked, false},
      {'increment, 'times_unlocked}
    });

    length(reaction.effects) == 3 || raise(E_ASSERT, "Should have 3 effects");
    reaction.effects[1].type == 'announce || raise(E_ASSERT, "First effect should be announce");
    reaction.effects[2].type == 'set || raise(E_ASSERT, "Second effect should be set");
    reaction.effects[3].type == 'increment || raise(E_ASSERT, "Third effect should be increment");

    return true;
  endverb

  verb test_compare (this none this) owner: HACKER flags: "rxd"
    "Test comparison operators.";
    this:compare(5, 'eq, 5) || raise(E_ASSERT, "5 == 5");
    !this:compare(5, 'eq, 3) || raise(E_ASSERT, "5 != 3");
    this:compare(5, 'ne, 3) || raise(E_ASSERT, "5 != 3");
    this:compare(5, 'gt, 3) || raise(E_ASSERT, "5 > 3");
    !this:compare(3, 'gt, 5) || raise(E_ASSERT, "3 not > 5");
    this:compare(3, 'lt, 5) || raise(E_ASSERT, "3 < 5");
    this:compare(5, 'ge, 5) || raise(E_ASSERT, "5 >= 5");
    this:compare(5, 'ge, 3) || raise(E_ASSERT, "5 >= 3");
    this:compare(5, 'le, 5) || raise(E_ASSERT, "5 <= 5");
    this:compare(3, 'le, 5) || raise(E_ASSERT, "3 <= 5");

    return true;
  endverb

  verb test_threshold_crossed (this none this) owner: HACKER flags: "rxd"
    "Test threshold crossing detection.";
    "Crossing from below to at/above";
    this:threshold_crossed(9, 10, 'ge, 10) || raise(E_ASSERT, "9->10 crosses >=10");
    this:threshold_crossed(5, 15, 'ge, 10) || raise(E_ASSERT, "5->15 crosses >=10");
    !this:threshold_crossed(10, 11, 'ge, 10) || raise(E_ASSERT, "10->11 already met >=10");
    !this:threshold_crossed(8, 9, 'ge, 10) || raise(E_ASSERT, "8->9 doesn't cross >=10");

    "Crossing equality";
    this:threshold_crossed(9, 10, 'eq, 10) || raise(E_ASSERT, "9->10 crosses ==10");
    !this:threshold_crossed(10, 10, 'eq, 10) || raise(E_ASSERT, "10->10 already met");
    this:threshold_crossed(11, 10, 'eq, 10) || raise(E_ASSERT, "11->10 crosses ==10");

    return true;
  endverb

  verb mk (this none this) owner: HACKER flags: "rxd"
    "Create a reaction flyweight. Parses and validates at creation time.";
    "Args: trigger, when_clause (0 or rule string), effects (list of effect specs)";
    {trigger, ?when_clause = 0, ?effects = {}} = args;

    "Validate trigger";
    this:validate_trigger(trigger);

    "Parse when clause if provided";
    parsed_when = 0;
    if (when_clause && typeof(when_clause) == STR)
      parsed_when = $rule_engine:parse_expression(when_clause);
    endif

    "Parse and validate effects";
    parsed_effects = {};
    for effect_spec in (effects)
      parsed_effects = {@parsed_effects, this:parse_effect(effect_spec)};
    endfor

    return <this,
      .trigger = trigger,
      .when = parsed_when,
      .effects = parsed_effects,
      .enabled = true,
      .fired_at = 0
    >;
  endverb

  verb validate_trigger (this none this) owner: HACKER flags: "rxd"
    "Validate a trigger specification.";
    {trigger} = args;

    "Event trigger - just a symbol";
    if (typeof(trigger) == SYM)
      return true;
    endif

    "Threshold trigger - {'when, 'prop, 'op, value}";
    if (typeof(trigger) == LIST)
      length(trigger) == 4 || raise(E_INVARG, "Threshold trigger must be {'when, 'prop, 'op, value}");
      {kind, prop, op, value} = trigger;
      kind == 'when || raise(E_INVARG, "Threshold trigger must start with 'when");
      typeof(prop) == SYM || raise(E_INVARG, "Property must be symbol");
      op in this.comparison_ops || raise(E_INVARG, "Invalid comparison operator: " + tostr(op));
      return true;
    endif

    raise(E_INVARG, "Trigger must be symbol or {'when, 'prop, 'op, value}");
  endverb

  verb parse_effect (this none this) owner: HACKER flags: "rxd"
    "Parse an effect spec into a validated flyweight.";
    {spec} = args;

    typeof(spec) == LIST || raise(E_INVARG, "Effect must be list");
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
      compiled_msg = typeof(msg) == STR ? $sub_utils:compile(msg) | msg;
      return <$reaction, .type = 'announce, .msg = compiled_msg>;

    elseif (effect_type == 'emote)
      {_, msg} = spec;
      compiled_msg = typeof(msg) == STR ? $sub_utils:compile(msg) | msg;
      return <$reaction, .type = 'emote, .msg = compiled_msg>;

    elseif (effect_type == 'tell)
      {_, target_var, msg} = spec;
      compiled_msg = typeof(msg) == STR ? $sub_utils:compile(msg) | msg;
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
    endif

    raise(E_INVARG, "Unhandled effect type: " + tostr(effect_type));
  endverb

  verb compare (this none this) owner: HACKER flags: "rxd"
    "Compare two values with an operator symbol.";
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
  endverb

  verb threshold_crossed (this none this) owner: HACKER flags: "rxd"
    "Check if a threshold was crossed (wasn't met before, is met now).";
    {old_value, new_value, op, threshold} = args;

    was_met = this:compare(old_value, op, threshold);
    now_met = this:compare(new_value, op, threshold);

    return now_met && !was_met;
  endverb

  verb execute (this none this) owner: HACKER flags: "rxd"
    "Execute this reaction in the given context.";
    "Context is map: ['Actor -> player, 'This -> object, 'Key -> iobj, ...]";
    {context} = args;

    "Check when clause if present";
    if (this.when && this.when != 0)
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
  endverb

  verb _resolve_msg (this none this) owner: HACKER flags: "rxd"
    "Resolve a message reference to a compiled template list.";
    "If msg is a symbol, looks up that property on target.";
    "If the property is a $msg_bag, picks randomly.";
    "Returns a list suitable for @-splat into $event:mk_info.";
    {msg, target} = args;

    "If it's a symbol, look up the property on target";
    if (typeof(msg) == SYM)
      prop_name = tostr(msg);
      prop_value = `target.(prop_name) ! E_PROPNF => 0';
      if (prop_value == 0)
        return {"(missing message: " + prop_name + ")"};
      endif
      "If it's a msg_bag, pick randomly";
      if (typeof(prop_value) == OBJ && isa(prop_value, $msg_bag))
        return prop_value:pick();
      endif
      "Otherwise use the property value directly (should be compiled list)";
      return prop_value;
    endif

    "Already a compiled list or other value";
    return msg;
  endverb

  verb execute_effect (this none this) owner: HACKER flags: "rxd"
    "Execute a single effect in context. Effect can be flyweight or raw list.";
    {effect, context, target} = args;

    "Parse list effects on the fly for convenience";
    if (typeof(effect) == LIST)
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
      "Create event with compiled $sub content, target as actor for pronoun resolution";
      msg = this:_resolve_msg(effect.msg, target);
      event = $event:mk_info(target, @msg):with_dobj(actor);
      if (valid(target.location))
        target.location:announce(event);
      endif

    elseif (effect.type == 'emote)
      "Object 'does' something - auto-prefix actor name like emote command";
      msg = this:_resolve_msg(effect.msg, target);
      event = $event:mk_emote(target, target.name, " ", @msg):with_dobj(actor);
      if (valid(target.location))
        target.location:announce(event);
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
      dest = typeof(effect.destination) == SYM ? context[effect.destination] | effect.destination;
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

    endif
  endverb

endobject
