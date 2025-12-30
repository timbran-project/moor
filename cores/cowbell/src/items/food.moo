object FOOD
  name: "Generic Food"
  parent: CONSUMABLE
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  fertile: true
  readable: true

  property bite_msg (owner: ARCH_WIZARD, flags: "rc") = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .capitalize = false, .for_self = "take", .type = 'self_alt, .for_others = "takes">,
    " a bite of ",
    <SUB, .capitalize = false, .type = 'article_the, .binding_name = 'd, .capitalize_binding = false>,
    "."
  };
  property consume_amounts (owner: ARCH_WIZARD, flags: "rc") = ["bite" -> 2, "devour" -> 99, "eat" -> 2, "nibble" -> 1];
  property devour_msg (owner: ARCH_WIZARD, flags: "rc") = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .capitalize = false, .for_self = "devour", .type = 'self_alt, .for_others = "devours">,
    " ",
    <SUB, .capitalize = false, .type = 'article_the, .binding_name = 'd, .capitalize_binding = false>,
    "."
  };
  property eat_msg (owner: ARCH_WIZARD, flags: "rc") = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .capitalize = false, .for_self = "eat", .type = 'self_alt, .for_others = "eats">,
    " some of ",
    <SUB, .capitalize = false, .type = 'article_the, .binding_name = 'd, .capitalize_binding = false>,
    "."
  };
  property munch_msg (owner: ARCH_WIZARD, flags: "rc") = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .capitalize = false, .for_self = "munch", .type = 'self_alt, .for_others = "munches">,
    " on ",
    <SUB, .capitalize = false, .type = 'article_the, .binding_name = 'd, .capitalize_binding = false>,
    "."
  };
  property nibble_msg (owner: ARCH_WIZARD, flags: "rc") = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .capitalize = false, .for_self = "nibble", .type = 'self_alt, .for_others = "nibbles">,
    " at ",
    <SUB, .capitalize = false, .type = 'article_the, .binding_name = 'd, .capitalize_binding = false>,
    "."
  };

  override consume_msg = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .capitalize = false, .for_self = "eat", .type = 'self_alt, .for_others = "eats">,
    " some of ",
    <SUB, .capitalize = false, .type = 'article_the, .binding_name = 'd, .capitalize_binding = false>,
    "."
  };
  override description = "Prototype for edible food items. Supports eat, bite, nibble, devour commands.";
  override finish_msg = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .capitalize = false, .for_self = "finish", .type = 'self_alt, .for_others = "finishes">,
    " eating ",
    <SUB, .capitalize = false, .type = 'article_the, .binding_name = 'd, .capitalize_binding = false>,
    "."
  };
  override import_export_hierarchy = {"items"};
  override import_export_id = "food";
  override object_documentation = {
    "# Food",
    "",
    "## Overview",
    "",
    "Edible items that players can eat. Inherits from $consumable. Supports multiple eating verbs with different portion sizes. Food is destroyed when empty by default.",
    "",
    "## Commands",
    "",
    "- `eat <food>` - consume entirely (or remaining portions)",
    "- `bite <food>` - take a medium bite",
    "- `nibble <food>` - take a tiny nibble",
    "- `devour <food>` / `munch <food>` - consume greedily",
    "",
    "## Properties",
    "",
    "Inherited from $consumable:",
    "- `portions`: Remaining portions (default: 1)",
    "- `max_portions`: Maximum portions",
    "- `consume_rule`: Access control rule",
    "- `on_finish`: `\"destroy\"` (default) or `\"keep\"`",
    "",
    "Food-specific:",
    "- `consume_amounts`: Map of verb to portion size (default: eat=all, bite=1, nibble=1, devour=all, munch=2)",
    "",
    "## Messages",
    "",
    "Each eating verb uses its own message property. Customize with `@set-message`:",
    "",
    "- `eat_msg`: Used by `eat` command",
    "- `bite_msg`: Used by `bite` command",
    "- `nibble_msg`: Used by `nibble` command",
    "- `devour_msg`: Used by `devour` command",
    "- `munch_msg`: Used by `munch` command",
    "- `finish_msg`: Shown when food is finished",
    "- `consume_msg`: Fallback if verb-specific message not found",
    "",
    "**Note:** Use `{nc}` for actor, `{the d}` for the food item, and `{verb|verbs}` for proper grammar.",
    "",
    "### Examples",
    "",
    "```",
    "@set-message apple.eat_msg {nc} {crunch|crunches} into {the d}.",
    "@set-message apple.nibble_msg {nc} {nibble|nibbles} daintily at {the d}.",
    "@set-message apple.finish_msg {nc} {toss|tosses} away the apple core.",
    "```",
    "",
    "## Rules",
    "",
    "Control who can eat with `consume_rule`:",
    "",
    "```",
    "@set-rule cake.consume_rule Accessor has(\"party invitation\")?",
    "```",
    "",
    "## Reactions",
    "",
    "Food fires these triggers:",
    "",
    "- `'on_consume`: Each bite/nibble/eat, bindings: `['Actor, 'Amount]`",
    "- `'on_empty`: When food is finished, bindings: `['Actor]`",
    "",
    "### Adding Reactions",
    "",
    "For reactions that announce messages:",
    "",
    "1. Create a message property:",
    "```",
    "@property pepper.spicy_msg {} rc",
    "```",
    "",
    "2. Set the message template:",
    "```",
    "@set-message pepper.spicy_msg {nc} {gasp|gasps} and {fan|fans} {p} mouth!",
    "```",
    "",
    "3. Add the reaction referencing it by symbol:",
    "```",
    "@add-reaction pepper.spicy_reaction 'on_consume 0 {{'announce, 'spicy_msg}}",
    "```",
    "",
    "Threshold reactions trigger when a property crosses a value:",
    "",
    "```",
    "@property cake.low_msg {} rc",
    "@set-message cake.low_msg The cake is almost gone!",
    "@add-reaction cake.low_reaction {'when, 'portions, 'le, 2} 0 {{'announce, 'low_msg}}",
    "```",
    "",
    "## Creating Food",
    "",
    "```moo",
    "apple = $food:create();",
    "apple:set_name_aliases(\"crisp apple\", {\"apple\"});",
    "apple.description = \"A perfectly ripe red apple.\";",
    "apple.portions = 4;",
    "apple.max_portions = 4;",
    "```"
  };

  verb "eat bite nibble devour munch" (this none none) owner: ARCH_WIZARD flags: "rd"
    "Handle eating food - command verb for eat/bite/nibble/devour/munch.";
    "Check if player has access to the food";
    if (this.location != player && this.location != player.location)
      event = $event:mk_error(player, "You don't have ", $sub:d(), "."):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    "Check if can consume";
    check = this:can_consume(player);
    if (!check['allowed])
      event = $event:mk_error(player, @check['reason]):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    "Get amount based on verb used";
    amount = this.consume_amounts[verb] || 1;
    is_finishing = amount >= this.portions;
    if (is_finishing)
      amount = this.portions;
    endif
    "Get verb-specific message";
    msg_prop = verb + "_msg";
    msg = `this.(msg_prop) ! E_PROPNF => this.consume_msg';
    "Cache finish_msg before consumption (object may be destroyed)";
    finish_msg = this.finish_msg;
    location = player.location;
    "Announce the eating";
    if (valid(location))
      event = $event:mk_social(player, @msg):with_dobj(this):with_audience('narrative);
      location:announce(event);
    endif
    "Announce finish BEFORE consumption if finishing (object will be destroyed)";
    if (is_finishing && valid(location))
      finish_event = $event:mk_social(player, @finish_msg):with_dobj(this):with_audience('narrative);
      location:announce(finish_event);
    endif
    "Do the consumption silently (we already announced)";
    this:do_consume(player, amount, true);
  endverb

  verb help_topics (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return help topics for food items.";
    {for_player, ?topic = ""} = args;
    my_topics = {$help:mk("eat", "Eat food", "Use 'eat <food>' to consume food you're holding or that's nearby. Eating consumes the whole portion.", {"consume"}, 'commands, {"bite", "nibble"}), $help:mk("bite", "Take a bite", "Use 'bite <food>' to take a small bite of food. Takes less than eating the whole thing.", {}, 'commands, {"eat", "nibble"}), $help:mk("nibble", "Nibble at food", "Use 'nibble <food>' to nibble delicately at food. Takes only a tiny portion.", {}, 'commands, {"eat", "bite"})};
    topic == "" && return my_topics;
    for t in (my_topics)
      t:matches(topic) && return t;
    endfor
    return 0;
  endverb
endobject