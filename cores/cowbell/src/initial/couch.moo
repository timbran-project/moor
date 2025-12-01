object COUCH
  name: "ratty couch"
  parent: SITTABLE
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override aliases = {"couch", "sofa", "ratty couch"};
  override description = "A well-worn brown couch that's seen better days. The cushions are slightly lumpy and there's a suspicious amount of black cat hair embedded in the fabric. Despite its shabby appearance, it looks comfortable enough for a quick rest - or for a grouchy cat to claim as his territory.";

  override seats = 3;
  override squeeze = 1;
  override sitting_verb = "lounging";
  override sitting_prep = "on";

  override sit_msg = {
    <SUB, .type = 'actor, .capitalize = true>,
    " ",
    <SUB, .type = 'self_alt, .for_self = "sink", .for_others = "sinks", .capitalize = false>,
    " into ",
    <SUB, .binding_name = 'This, .type = 'article_the, .capitalize = false>,
    ", stirring up a small cloud of cat hair."
  };

  override stand_msg = {
    <SUB, .type = 'actor, .capitalize = true>,
    " ",
    <SUB, .type = 'self_alt, .for_self = "stand", .for_others = "stands", .capitalize = false>,
    " up from ",
    <SUB, .binding_name = 'This, .type = 'article_the, .capitalize = false>,
    ", brushing off some cat hair."
  };

  override import_export_id = "couch";
  override import_export_hierarchy = {"initial"};

  override get_denied_msg = {"The couch is far too heavy to pick up."};
  override get_rule = <RULE, .name = 'is_portable, .head = 'is_portable, .body = {{'is_portable, 'This}}, .variables = {'This}>;

  property henri_disturbed_reaction (owner: HACKER, flags: "r") = <REACTION, .trigger = 'on_sit, .when = <RULE, .name = 'henri_sitting, .head = 'henri_sitting, .body = {{'is_sitting, 'This, HENRI}, {'not_is, 'This, 'Actor, HENRI}}, .variables = {'This, 'Actor}>, .effects = {{'trigger, HENRI, 'on_couch_intruder}}, .enabled = true, .fired_at = 0>;

  verb fact_is_portable (this none this) owner: HACKER flags: "rxd"
    "Couches are not portable.";
    return false;
  endverb

  verb fact_is_sitting (this none this) owner: HACKER flags: "rxd"
    "Rule predicate: Is target sitting on this furniture?";
    {furniture, who} = args;
    return who in furniture.sitting;
  endverb

  verb fact_not_is (this none this) owner: HACKER flags: "rxd"
    "Rule predicate: Are two values not equal? First arg is this (for rule dispatch).";
    {_, a, b} = args;
    return a != b;
  endverb
endobject
