object COUCH
  name: "ratty couch"
  parent: SITTABLE
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  property henri_disturbed_reaction (owner: HACKER, flags: "r") = <#69, .when = <#63, .name = 'henri_sitting, .head = 'henri_sitting, .body = {{'is_sitting, 'This, HENRI}, {'not_is, 'This, 'Actor, HENRI}}, .variables = {'This, 'Actor}>, .trigger = 'on_sit, .effects = {{'trigger, HENRI, 'on_couch_intruder}}, .enabled = true, .fired_at = 0>;

  override aliases = {"couch", "sofa", "ratty couch"};
  override description = "A well-worn brown couch that's seen better days. The cushions are slightly lumpy and there's a suspicious amount of black cat hair embedded in the fabric. Despite its shabby appearance, it looks comfortable enough for a quick rest - or for a grouchy cat to claim as his territory.";
  override get_denied_msg = {"The couch is far too heavy to pick up."};
  override get_rule = <#63, .name = 'is_portable, .head = 'is_portable, .body = {{'is_portable, 'This}}, .variables = {'This}>;
  override import_export_hierarchy = {"initial"};
  override import_export_id = "couch";
  override seats = 3;
  override sit_msg = {
    <#19, .type = 'actor, .capitalize = true>,
    " ",
    <#19, .type = 'self_alt, .for_self = "sink", .for_others = "sinks", .capitalize = false>,
    " into ",
    <#19, .binding_name = 'This, .type = 'article_the, .capitalize = false>,
    ", stirring up a small cloud of cat hair."
  };
  override sitting_verb = "lounging";
  override squeeze = 1;
  override stand_msg = {
    <#19, .type = 'actor, .capitalize = true>,
    " ",
    <#19, .type = 'self_alt, .for_self = "stand", .for_others = "stands", .capitalize = false>,
    " up from ",
    <#19, .binding_name = 'This, .type = 'article_the, .capitalize = false>,
    ", brushing off some cat hair."
  };

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