object KIBBLE_CUPBOARD
  name: "a wooden cupboard"
  parent: CONTAINER
  location: FIRST_ROOM
  owner: ARCH_WIZARD
  readable: true

  property kibble_taken_reaction (owner: HACKER, flags: "r") = <REACTION, .when = <RULE, .name = 'kibble_check, .body = {{'isa, 'Item, CAT_KIBBLE}}, .head = 'kibble_check, .variables = {'Item}>, .trigger = 'on_take, .effects = {{'trigger, HENRI, 'on_kibble_taken}}, .enabled = true, .fired_at = 0>;
  property waft_reaction (owner: HACKER, flags: "r") = <REACTION, .when = 0, .trigger = 'on_open, .effects = {
      {'announce, "A waft of kibble-scented air escapes from the cupboard."},
      {'trigger, HENRI, 'on_cupboard_open}
    }, .enabled = true, .fired_at = 0>;

  override aliases = {"cupboard", "cabinet", "wooden cupboard"};
  override close_msg = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .for_self = "close", .type = 'self_alt, .for_others = "closes">,
    " ",
    <SUB, .capitalize = false, .type = 'dobj>,
    ", sealing away the kibble."
  };
  override description = "A sturdy wooden cupboard with a brass lock on the door. It has a faint aroma of cat food emanating from within.";
  override get_denied_msg = {"The cupboard is far too heavy and unwieldy to pick up."};
  override get_rule = <RULE, .name = 'is_portable, .body = {{'is_portable, 'This}}, .head = 'is_portable, .variables = {'This}>;
  override import_export_hierarchy = {"initial"};
  override import_export_id = "kibble_cupboard";
  override lock_denied_msg = {
    <SUB, .capitalize = true, .type = 'iobj>,
    " won't lock without the proper key."
  };
  override lock_msg = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .for_self = "lock", .type = 'self_alt, .for_others = "locks">,
    " ",
    <SUB, .capitalize = false, .type = 'iobj>,
    " with ",
    <SUB, .capitalize = false, .type = 'dobj>,
    " with a satisfying click."
  };
  override lock_rule = <RULE, .name = 'cupboard_lock_rule, .body = {{'is, 'Key, BRASS_KEY}}, .head = 'cupboard_lock_rule, .variables = {'Key}>;
  override locked = true;
  override open = false;
  override open_locked_msg = {
    <SUB, .capitalize = true, .type = 'dobj>,
    " is locked tight. You'll need to unlock it first."
  };
  override open_msg = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .for_self = "open", .type = 'self_alt, .for_others = "opens">,
    " ",
    <SUB, .capitalize = false, .type = 'dobj>,
    ", revealing Henri's kibble storage."
  };
  override put_denied_msg = {
    <SUB, .capitalize = true, .type = 'iobj>,
    " is closed. You'll need to open it first."
  };
  override take_denied_msg = {
    <SUB, .capitalize = true, .type = 'iobj>,
    " is closed. You'll need to open it first."
  };
  override unlock_denied_msg = {
    <SUB, .capitalize = true, .type = 'iobj>,
    " won't budge. It needs the right key."
  };
  override unlock_msg = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .for_self = "unlock", .type = 'self_alt, .for_others = "unlocks">,
    " ",
    <SUB, .capitalize = false, .type = 'iobj>,
    " with ",
    <SUB, .capitalize = false, .type = 'dobj>,
    ". The brass lock clicks open."
  };
  override unlock_rule = <RULE, .name = 'cupboard_unlock_rule, .body = {{'is, 'Key, BRASS_KEY}}, .head = 'cupboard_unlock_rule, .variables = {'Key}>;

  verb fact_is_portable (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Cupboards are not portable.";
    return false;
  endverb
endobject