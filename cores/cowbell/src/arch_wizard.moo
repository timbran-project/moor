object ARCH_WIZARD [
  import_export_id -> "arch_wizard"
]
  name: "ArchWizard"
  parent: PLAYER
  location: FIRST_ROOM
  owner: ARCH_WIZARD
  player: true
  wizard: true
  programmer: true

  override admin_features (owner: ARCH_WIZARD, flags: "") = {ADMIN_FEATURES};
  override authoring_features (owner: ARCH_WIZARD, flags: "") = PROG_FEATURES;
  override description (owner: ARCH_WIZARD, flags: "rc") = "The arch-wizard account with full system privileges.";
  override features (owner: ARCH_WIZARD, flags: "rc") = {SOCIAL_FEATURES, MAIL_FEATURES, WIZ_FEATURES};
  override is_builder (owner: ARCH_WIZARD, flags: "") = true;
  override password (owner: ARCH_WIZARD, flags: "c") = <PASSWORD, {"$argon2id$v=19$m=4096,t=3,p=1$SUkraXpNSC9KR2VQeHpKanZkMVF6Zw$HRQz7Lc+ZlulVXprOi4Vp5MxjUXtiAoo17sq/LRgmF8"}>;
endobject
