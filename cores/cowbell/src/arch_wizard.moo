object ARCH_WIZARD
  name: "ArchWizard"
  parent: PLAYER
  location: FIRST_ROOM
  owner: ARCH_WIZARD
  player: true
  wizard: true
  programmer: true

  override admin_features = WIZ_FEATURES;
  override authoring_features = PROG_FEATURES;
  override description = "The arch-wizard account with full system privileges.";
  override import_export_id = "arch_wizard";
  override is_builder = true;
  override password = <PASSWORD, {"$argon2id$v=19$m=4096,t=3,p=1$SUkraXpNSC9KR2VQeHpKanZkMVF6Zw$HRQz7Lc+ZlulVXprOi4Vp5MxjUXtiAoo17sq/LRgmF8"}>;
endobject