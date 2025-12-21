object KIBBLE_CUPBOARD
  name: "a wooden cupboard"
  parent: CONTAINER
  location: FIRST_ROOM
  owner: ARCH_WIZARD
  readable: true

  property kibble_taken_reaction (owner: HACKER, flags: "r") = <#69, .when = <#63, .name = 'kibble_check, .head = 'kibble_check, .body = {{'isa, 'Item, CAT_KIBBLE}}, .variables = {'Item}>, .trigger = 'on_take, .effects = {{'trigger, HENRI, 'on_kibble_taken}}, .enabled = true, .fired_at = 0>;
  property waft_reaction (owner: HACKER, flags: "r") = <#69, .when = 0, .trigger = 'on_open, .effects = {
      {'announce, "A waft of kibble-scented air escapes from the cupboard."},
      {'trigger, HENRI, 'on_cupboard_open}
    }, .enabled = true, .fired_at = 0>;

  override aliases = {"cupboard", "cabinet", "wooden cupboard"};
  override close_msg = {
    <#19, .type = 'actor, .capitalize = true>,
    " ",
    <#19, .type = 'self_alt, .for_self = "close", .for_others = "closes">,
    " ",
    <#19, .type = 'dobj, .capitalize = false>,
    ", sealing away the kibble."
  };
  override description = "A sturdy wooden cupboard with a brass lock on the door. It has a faint aroma of cat food emanating from within.";
  override import_export_hierarchy = {"initial"};
  override import_export_id = "kibble_cupboard";
  override lock_denied_msg = {
    <#19, .type = 'iobj, .capitalize = true>,
    " won't lock without the proper key."
  };
  override lock_msg = {
    <#19, .type = 'actor, .capitalize = true>,
    " ",
    <#19, .type = 'self_alt, .for_self = "lock", .for_others = "locks">,
    " ",
    <#19, .type = 'iobj, .capitalize = false>,
    " with ",
    <#19, .type = 'dobj, .capitalize = false>,
    " with a satisfying click."
  };
  override lock_rule = <#63, .name = 'cupboard_lock_rule, .head = 'cupboard_lock_rule, .body = {{'is, 'Key, BRASS_KEY}}, .variables = {'Key}>;
  override locked = true;
  override open = false;
  override open_locked_msg = {
    <#19, .type = 'dobj, .capitalize = true>,
    " is locked tight. You'll need to unlock it first."
  };
  override open_msg = {
    <#19, .type = 'actor, .capitalize = true>,
    " ",
    <#19, .type = 'self_alt, .for_self = "open", .for_others = "opens">,
    " ",
    <#19, .type = 'dobj, .capitalize = false>,
    ", revealing Henri's kibble storage."
  };
  override put_denied_msg = {
    <#19, .type = 'iobj, .capitalize = true>,
    " is closed. You'll need to open it first."
  };
  override take_denied_msg = {
    <#19, .type = 'iobj, .capitalize = true>,
    " is closed. You'll need to open it first."
  };
  override unlock_denied_msg = {
    <#19, .type = 'iobj, .capitalize = true>,
    " won't budge. It needs the right key."
  };
  override unlock_msg = {
    <#19, .type = 'actor, .capitalize = true>,
    " ",
    <#19, .type = 'self_alt, .for_self = "unlock", .for_others = "unlocks">,
    " ",
    <#19, .type = 'iobj, .capitalize = false>,
    " with ",
    <#19, .type = 'dobj, .capitalize = false>,
    ". The brass lock clicks open."
  };
  override unlock_rule = <#63, .name = 'cupboard_unlock_rule, .head = 'cupboard_unlock_rule, .body = {{'is, 'Key, BRASS_KEY}}, .variables = {'Key}>;
endobject