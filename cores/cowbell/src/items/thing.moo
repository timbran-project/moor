// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later
object THING [
  import_export_id -> "thing",
  import_export_hierarchy -> {"items"}
]
  name: "Generic Thing"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: HACKER
  fertile: true
  readable: true

  property drop_denied_msg (owner: HACKER, flags: "rc") = {"You can't drop that."};
  property drop_msg (owner: HACKER, flags: "rc") = {
    <SUB, .capitalize = true, .type = 'actor>,
    " dropped ",
    <SUB, .capitalize = false, .type = 'dobj>,
    "."
  };
  property drop_rule (owner: HACKER, flags: "rc") = 0;
  property get_denied_msg (owner: HACKER, flags: "rc") = {"You can't pick that up."};
  property get_msg (owner: HACKER, flags: "rc") = {
    <SUB, .capitalize = true, .type = 'actor>,
    " picked up ",
    <SUB, .capitalize = false, .type = 'dobj>,
    "."
  };
  property get_rule (owner: HACKER, flags: "rc") = 0;
  property integrated_description (owner: HACKER, flags: "rc") = "";
  property is_countable_noun (owner: HACKER, flags: "rc") = true;
  property is_plural_noun (owner: HACKER, flags: "rc") = false;
  property is_proper_noun_name (owner: HACKER, flags: "rc") = false;
  property portable (owner: HACKER, flags: "rc") = true;
  property pronouns (owner: HACKER, flags: "rc") = <PRONOUNS, .verb_be = "is", .verb_have = "has", .is_plural = false, .display = "it/its", .ps = "it", .po = "it", .pp = "its", .pq = "its", .pr = "itself">;
  property unlocks (owner: HACKER, flags: "rc") = #-1;

  override description (owner: HACKER, flags: "rc") = "Generic thing prototype that is the basis for most items in the world.";
  override object_documentation (owner: HACKER, flags: "rc") = {
    "# Generic Things",
    "",
    "## Overview",
    "",
    "Things are the base class for most items in the world. They can be picked up, dropped, and moved around. Things form the foundation for more specialized items like containers and wearables.",
    "",
    "## Properties",
    "",
    "### pronouns",
    "",
    "Grammatical properties for this object (pronouns, plurality, noun type).",
    "",
    "- Default: it/its pronouns, singular, countable",
    "- Can be customized per item or use preset pronoun objects",
    "",
    "### is_plural_noun",
    "",
    "Whether this object should be treated as grammatically plural.",
    "",
    "- Default: `false`",
    "",
    "### is_countable_noun",
    "",
    "Whether this object can use articles like 'a' or 'the'.",
    "",
    "- Default: `true`",
    "",
    "### is_proper_noun_name",
    "",
    "Whether this object is a proper noun (like a name) that doesn't need articles.",
    "",
    "- Default: `false`",
    "",
    "### integrated_description",
    "",
    "Text that appears in the room description when this thing is present.",
    "",
    "- Default: empty string (not integrated)",
    "- Can be set to add flavor text about the item to the room description",
    "",
    "### get_msg and drop_msg",
    "",
    "Customizable messages shown when the item is picked up or dropped.",
    "",
    "Customize using the `@set-message` command:",
    "",
    "```",
    "@set-message sword.get_msg {nc} {grasp|grasps} {d} firmly.",
    "@set-message sword.drop_msg {nc} {release|releases} {d} carefully.",
    "```",
    "",
    "Template tokens:",
    "- `{nc}` - Actor name (capitalized)",
    "- `{grasp|grasps}` - Self-alternation verb",
    "- `{d}` - Direct object (the item)",
    "",
    "## Commands",
    "",
    "### get / take",
    "",
    "```",
    "get <item>",
    "take <item>",
    "```",
    "",
    "Picks up an item and adds it to inventory.",
    "",
    "### drop",
    "",
    "```",
    "drop <item>",
    "```",
    "",
    "Removes an item from inventory and places it in the current location.",
    "",
    "## Verbs",
    "",
    "### pronouns()",
    "",
    "Returns the pronoun set for this object.",
    "",
    "### is_plural()",
    "",
    "Returns whether this object is grammatically plural.",
    "",
    "### is_countable()",
    "",
    "Returns whether this object is countable (can use articles).",
    "",
    "### is_proper_noun()",
    "",
    "Returns whether this object is a proper noun.",
    "",
    "### integrate_description()",
    "",
    "Returns the integrated description if set, or `false` otherwise.",
    "",
    "## Example: Creating a Sword",
    "",
    "```moo",
    "sword = create($thing);",
    "sword:set_name(\"a gleaming sword\");",
    "sword.description = \"A well-crafted sword with a sharp blade.\";",
    "sword.integrated_description = \"a sword lies here, glinting in the light\";",
    "```"
  };

  method pronouns owner: ARCH_WIZARD
    "Return the pronoun set for this object (object or flyweight).";
    set_task_perms(caller_perms());
    return this.pronouns;
  endmethod

  method is_plural owner: ARCH_WIZARD
    "Returns whether this object should be treated as a plural noun.";
    "Things are singular by default but can be set to plural.";
    return this.is_plural_noun;
  endmethod

  method is_countable owner: ARCH_WIZARD
    "Returns whether this object is countable in English grammar.";
    "Things are countable by default (can use 'a' or 'the').";
    return this.is_countable_noun;
  endmethod

  method is_proper_noun owner: ARCH_WIZARD
    "Returns whether this object should be treated as a proper noun.";
    "Things are common nouns by default, not proper nouns.";
    return this.is_proper_noun_name;
  endmethod

  method integrate_description owner: ARCH_WIZARD
    "Return integrated description if set, or false. Integrated descriptions become part of the room description.";
    set_task_perms(caller_perms());
    desc = this.integrated_description;
    if (desc && desc != "")
      return desc;
    endif
    return false;
  endmethod

  method "pronoun_*" owner: ARCH_WIZARD
    "Get pronoun from either preset object or custom flyweight.";
    set_task_perms(caller_perms());
    ptype = tosym(verb[9..length(verb)]);
    p = this:pronouns();
    ptype == 'subject && return p.ps;
    ptype == 'object && return p.po;
    ptype == 'possessive && args[1] == 'adj && return p.pp;
    ptype == 'possessive && args[2] == 'noun && return p.pq;
    ptype == 'reflexive && return p.pr;
    raise(E_INVARG);
  endmethod

  method can_get owner: ARCH_WIZARD
    "Check if actor can pick up this object. Returns true/false.";
    {?who = player} = args;
    "Not portable means never allowed";
    !this.portable && return false;
    "No rule means always allowed";
    this.get_rule == 0 && return true;
    "Evaluate rule with context";
    context = ['Actor -> who, 'This -> this];
    result = $rule_engine:evaluate(this.get_rule, context);
    return result['success];
  endmethod

  method can_drop owner: ARCH_WIZARD
    "Check if actor can drop this object. Returns true/false.";
    {?who = player} = args;
    "No rule means always allowed";
    this.drop_rule == 0 && return true;
    "Evaluate rule with context";
    context = ['Actor -> who, 'This -> this];
    result = $rule_engine:evaluate(this.drop_rule, context);
    return result['success];
  endmethod

  method take_reachable owner: ARCH_WIZARD
    "Return whether an item is on the actor's floor or in an open nearby container.";
    "Args: {item, who}. This geometry check does not grant permission to take the item.";
    const {item, who} = args;
    valid(item) && valid(who) && valid(who.location) || return false;
    const source = item.location;
    source == who.location && return true;
    valid(source) && isa(source, $container) || return false;
    return source.open && (source.location == who || source.location == who.location);
  endmethod

  method do_get owner: ARCH_WIZARD
    "Move item to actor's inventory. Returns true. Optional silent flag.";
    "Only callable by this object itself";
    caller != this && raise(E_PERM, "do_get must be called by this object");
    {who, ?silent = false} = args;
    $thing:take_reachable(this, who) || raise(E_PERM, "That is no longer within reach.");
    old_location = this.location;
    if (old_location != who.location)
      const take_policy = old_location.take_rule;
      old_location:can_take_from(who, this)['allowed]
        || raise(E_PERM, "You can't take that from its container.");
      old_location.take_rule == take_policy
        || raise(E_PERM, "The container's access rules changed. Please try again.");
    endif
    "Container policy callbacks may suspend; recheck the source before moving.";
    this.location == old_location && $thing:take_reachable(this, who)
      || raise(E_PERM, "That is no longer within reach.");
    this:moveto(who);
    if (!silent && isa(old_location, $room))
      event = $event:mk_moved(who, @this.get_msg):with_dobj(this):with_iobj(who);
      old_location:announce(event);
    endif
    return true;
  endmethod

  method do_drop owner: ARCH_WIZARD
    "Drop item from actor to their location. Returns true. Optional silent flag.";
    "Only callable by this object itself";
    caller != this && raise(E_PERM, "do_drop must be called by this object");
    {who, ?silent = false} = args;
    this.location == who || raise(E_PERM, "You no longer have that to drop.");
    new_location = who.location;
    valid(new_location) || raise(E_PERM, "There is nowhere to drop that here.");
    this:moveto(new_location);
    if (!silent)
      event = $event:mk_moved(who, @this.drop_msg):with_dobj(this):with_iobj(who);
      new_location:announce(event);
    endif
    return true;
  endmethod

  verb get (this none none) owner: ARCH_WIZARD flags: "rxd" [
    ui -> ["label" -> "Take"]
  ]
    "Get/take an object - command handler";
    set_task_perms(caller_perms());
    if (this.location == player)
      event = $event:mk_error(player, "You already have ", $sub:d(), "."):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    if (!$thing:take_reachable(this, player))
      player:inform_current($event:mk_error(player, "That is no longer within reach."));
      return;
    endif
    if (!this:can_get(player))
      event = $event:mk_error(player, @this.get_denied_msg):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    if (!player:acceptable(this))
      event = $event:mk_no_accept(player, $sub:nc(), " can't put ", $sub:d(), " in ", $sub:ic(), "."):with_dobj(this):with_iobj(player);
      player:inform_current(event);
      return;
    endif
    try
      this:do_get(player);
    except e (E_PERM)
      msg = length(e) > 2 ? e[2] | "You don't have permission to take that.";
      event = $event:mk_error(player, msg):with_dobj(this);
      player:inform_current(event);
    endtry
  endverb

  verb drop (this none none) owner: ARCH_WIZARD flags: "rxd"
    "Drop an object from inventory - command handler";
    set_task_perms(caller_perms());
    if (this.location != player)
      event = $event:mk_error(player, "You don't have ", $sub:d(), " to drop."):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    if (!this:can_drop(player))
      event = $event:mk_error(player, @this.drop_denied_msg):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    if (!player.location:acceptable(this))
      event = $event:mk_error(player, "You can't drop ", $sub:d(), " here."):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    try
      this:do_drop(player);
    except e (E_PERM)
      msg = length(e) > 2 ? e[2] | "You don't have permission to drop that.";
      event = $event:mk_error(player, msg):with_dobj(this);
      player:inform_current(event);
    endtry
  endverb

  method acceptable owner: ARCH_WIZARD
    set_task_perms(caller_perms());
    return false;
  endmethod

  method "action_get action_take" owner: ARCH_WIZARD
    "Action handler for reactions: make actor pick up this item.";
    set_task_perms(this.owner);
    {who, context} = args;
    "Must be reachable: in same room, or in a container in same room";
    this.location == who && return false;
    if (this.location != who.location)
      "Not in same room - check if in a container in the room";
      if (!isa(this.location, $container) || this.location.location != who.location)
        return false;
      endif
    endif
    !this:can_get(who) && return false;
    !who:acceptable(this) && return false;
    return this:do_get(who);
  endmethod

  method action_drop owner: ARCH_WIZARD
    "Action handler for reactions: make actor drop this item.";
    set_task_perms(this.owner);
    {who, context} = args;
    this.location != who && return false;
    !this:can_drop(who) && return false;
    !who.location:acceptable(this) && return false;
    return this:do_drop(who);
  endmethod

  method action_put owner: ARCH_WIZARD
    "Action handler for reactions: put this item into a container.";
    set_task_perms(this.owner);
    {who, context, dest} = args;
    this.location != who && return false;
    !this:can_drop(who) && return false;
    "Delegate to container's action_put_into if available";
    if (respond_to(dest, 'action_put_into))
      return dest:action_put_into(who, context, this);
    endif
    "Fallback for non-container destinations: check acceptable and move";
    !dest:acceptable(this) && return false;
    this:moveto(dest);
    return true;
  endmethod

  method help_topics owner: ARCH_WIZARD
    "Return help topics - $thing defers to global get/drop topics.";
    {for_player, ?topic = ""} = args;
    "Basic get/drop covered by global help - things can override for special behavior";
    return topic == "" ? {} | 0;
  endmethod

  verb fact_unlocks (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Rule engine predicate: Key unlocks(Target)?";
    "Returns target if this object's .unlocks property matches the target.";
    "Rule engine passes (this_obj, target) as args.";
    {_, target} = args;
    unlocks = `this.unlocks ! E_PROPNF => #-1';
    if (unlocks == target)
      return target;
    endif
    return;
  endverb

  method inspection_state owner: ARCH_WIZARD
    "Describe custody and reach without running transfer policy callbacks.";
    const {?who = player} = args;
    this.location == who && return {"Carrying"};
    return $thing:take_reachable(this, who) ? {"Nearby"} | {"Out of reach"};
  endmethod

  method inspection_actions owner: ARCH_WIZARD
    "Suggest the current transfer and object commands; the parser checks policy when submitted.";
    const {?who = player} = args;
    const actions = pass(who);
    this.location != who && !$thing:take_reachable(this, who) && return {actions[1]};
    const carrying = this.location == who;
    const transfer = ["id" -> "transfer", "label" -> carrying ? "Drop" | "Take",
      "command" -> (carrying ? "drop " | "get ") + tostr(this),
      "action" -> $thing:command_action(carrying ? "drop" | "get", this:name())];
    return carrying || this.portable ? {actions[1], transfer, @actions[2..$]} | actions;
  endmethod

  method fact_is_portable owner: ARCH_WIZARD
    return this.portable;
  endmethod

  method test_grammar_and_description_defaults owner: HACKER
    "Cover default thing grammar helpers and integrated descriptions.";
    thing = this:create(true);
    thing.name = "test pebble";
    $test_utils:assert_eq(thing:pronouns(), this.pronouns, "things should inherit default pronouns");
    $test_utils:assert_false(thing:is_plural(), "things should be singular by default");
    $test_utils:assert_true(thing:is_countable(), "things should be countable by default");
    $test_utils:assert_false(thing:is_proper_noun(), "things should not be proper nouns by default");
    $test_utils:assert_eq(thing:pronoun_subject(), "it", "default subject pronoun");
    $test_utils:assert_eq(thing:pronoun_object(), "it", "default object pronoun");
    $test_utils:assert_eq(thing:pronoun_possessive('adj, 0), "its", "default possessive adjective");
    $test_utils:assert_eq(thing:pronoun_possessive(0, 'noun), "its", "default possessive noun");
    $test_utils:assert_eq(thing:pronoun_reflexive(), "itself", "default reflexive pronoun");
    $test_utils:assert_false(thing:integrate_description(), "empty integrated description should be false");
    thing.integrated_description = "a test pebble rests here";
    $test_utils:assert_eq(thing:integrate_description(), "a test pebble rests here", "integrated description should return text");
    return true;
  endmethod

  method test_portability_and_rule_defaults owner: HACKER
    "Cover default get/drop permission helpers and portability facts.";
    thing = this:create(true);
    thing.name = "test token";
    $test_utils:assert_true(thing:can_get(player), "portable things should be gettable by default");
    $test_utils:assert_true(thing:can_drop(player), "things should be droppable by default");
    $test_utils:assert_true(thing:fact_is_portable(), "fact_is_portable should reflect default portability");
    thing.portable = false;
    $test_utils:assert_false(thing:can_get(player), "non-portable things should not be gettable");
    $test_utils:assert_false(thing:fact_is_portable(), "fact_is_portable should reflect changed portability");
    $test_utils:assert_true(thing:can_drop(player), "portable flag should not block can_drop");
    $test_utils:assert_false(thing:acceptable(thing), "plain things should not accept contents");
    return true;
  endmethod

  method test_unlock_fact_and_inspection owner: HACKER
    "Cover unlock facts and basic inspection metadata.";
    key = this:create(true);
    target = this:create(true);
    key.name = "test key";
    key.description = "A key used by the unit tests.";
    target.name = "test lock";
    key.unlocks = target;
    $test_utils:assert_eq(key:fact_unlocks(key, target), target, "fact_unlocks should return matching target");
    $test_utils:assert_eq(key:fact_unlocks(key, this), 0, "fact_unlocks should return falsey for non-matching targets");
    data = key:inspection(player);
    $test_utils:assert_eq(data["title"], "test key", "inspection should include title");
    $test_utils:assert_eq(data["description"], "A key used by the unit tests.", "inspection should include description");
    $test_utils:assert_type(data["actions"], TYPE_LIST, "inspection should include actions list");
    return true;
  endmethod
endobject
