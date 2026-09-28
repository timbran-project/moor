object TEST_PLAYER [
  import_export_id -> "test_player",
  import_export_hierarchy -> {"initial"}
]
  name: "Test_Player"
  parent: PLAYER
  location: FIRST_ROOM
  owner: TEST_PLAYER
  player: true
  programmer: true
  readable: true

  override authoring_features (owner: ARCH_WIZARD, flags: "") = PROG_FEATURES;
  override description (owner: TEST_PLAYER, flags: "rc") = "A test player account with programmer privileges for development and testing.";
  override is_builder (owner: ARCH_WIZARD, flags: "") = true;
  override password (owner: TEST_PLAYER, flags: "c") = <PASSWORD, {"$argon2id$v=19$m=4096,t=3,p=1$eGMybURGTUFoTFlWbG5yUXZHZXdCZw$V7tP3V8q1AX0Rytaz7B57DbQfjyiDQ7ULcli/UZ2SoQ"}>;
endobject
