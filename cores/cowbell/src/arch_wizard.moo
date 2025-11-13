object ARCH_WIZARD
  name: "ArchWizard"
  parent: PLAYER
  location: FIRST_ROOM
  owner: ARCH_WIZARD
  player: true
  wizard: true
  programmer: true

  override description = "The arch-wizard account with full system privileges.";
  override import_export_id = "arch_wizard";
  override password = <#11, {"$argon2id$v=19$m=4096,t=3,p=1$SUkraXpNSC9KR2VQeHpKanZkMVF6Zw$HRQz7Lc+ZlulVXprOi4Vp5MxjUXtiAoo17sq/LRgmF8"}>;
  override wizard_granted_features = {BUILDER_FEATURES, PROG_FEATURES, WIZ_FEATURES};
endobject