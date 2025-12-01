object KIBBLE_CUPBOARD
  name: "a wooden cupboard"
  parent: CONTAINER
  location: FIRST_ROOM
  owner: ARCH_WIZARD
  readable: true

  override aliases = {"cupboard", "cabinet", "wooden cupboard"};
  override description = "A sturdy wooden cupboard with a brass lock on the door. It has a faint aroma of cat food emanating from within.";
  override import_export_hierarchy = {"initial"};
  override import_export_id = "kibble_cupboard";

  override open = false;
  override locked = true;

  override lock_msg = {<SUB, .capitalize = true, .type = 'actor>, " ", <SUB, .for_self = "lock", .for_others = "locks", .type = 'self_alt>, " ", <SUB, .capitalize = false, .type = 'iobj>, " with ", <SUB, .capitalize = false, .type = 'dobj>, " with a satisfying click."};
  override unlock_msg = {<SUB, .capitalize = true, .type = 'actor>, " ", <SUB, .for_self = "unlock", .for_others = "unlocks", .type = 'self_alt>, " ", <SUB, .capitalize = false, .type = 'iobj>, " with ", <SUB, .capitalize = false, .type = 'dobj>, ". The brass lock clicks open."};
  override open_msg = {<SUB, .capitalize = true, .type = 'actor>, " ", <SUB, .for_self = "open", .for_others = "opens", .type = 'self_alt>, " ", <SUB, .capitalize = false, .type = 'dobj>, ", revealing Henri's kibble storage."};
  override close_msg = {<SUB, .capitalize = true, .type = 'actor>, " ", <SUB, .for_self = "close", .for_others = "closes", .type = 'self_alt>, " ", <SUB, .capitalize = false, .type = 'dobj>, ", sealing away the kibble."};

  override lock_denied_msg = {<SUB, .capitalize = true, .type = 'iobj>, " won't lock without the proper key."};
  override unlock_denied_msg = {<SUB, .capitalize = true, .type = 'iobj>, " won't budge. It needs the right key."};
  override take_denied_msg = {<SUB, .capitalize = true, .type = 'iobj>, " is closed. You'll need to open it first."};
  override put_denied_msg = {<SUB, .capitalize = true, .type = 'iobj>, " is closed. You'll need to open it first."};
  override open_locked_msg = {<SUB, .capitalize = true, .type = 'dobj>, " is locked tight. You'll need to unlock it first."};

  override lock_rule = <RULE, .name = 'cupboard_lock_rule, .head = 'cupboard_lock_rule, .body = {{'is, 'Key, BRASS_KEY}}, .variables = {'Key}>;
  override unlock_rule = <RULE, .name = 'cupboard_unlock_rule, .head = 'cupboard_unlock_rule, .body = {{'is, 'Key, BRASS_KEY}}, .variables = {'Key}>;

  property waft_reaction (owner: HACKER, flags: "r") = <REACTION, .trigger = 'on_open, .when = 0, .effects = {{'announce, "A waft of kibble-scented air escapes from the cupboard."}, {'trigger, HENRI, 'on_cupboard_open}}, .enabled = true, .fired_at = 0>;
  property kibble_taken_reaction (owner: HACKER, flags: "r") = <REACTION, .trigger = 'on_take, .when = <RULE, .name = 'kibble_check, .head = 'kibble_check, .body = {{'isa, 'Item, CAT_KIBBLE}}, .variables = {'Item}>, .effects = {{'trigger, HENRI, 'on_kibble_taken}}, .enabled = true, .fired_at = 0>;
endobject
