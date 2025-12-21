object TEST_PLAYER
  name: "Test_Player"
  parent: PLAYER
  location: FIRST_ROOM
  owner: TEST_PLAYER
  player: true
  programmer: true
  readable: true

  override authoring_features = PROG_FEATURES;
  override description = "A test player account with programmer privileges for development and testing.";
  override import_export_hierarchy = {"initial"};
  override import_export_id = "test_player";
  override is_builder = true;
  override password = <#16, {"$argon2id$v=19$m=4096,t=3,p=1$eGMybURGTUFoTFlWbG5yUXZHZXdCZw$V7tP3V8q1AX0Rytaz7B57DbQfjyiDQ7ULcli/UZ2SoQ"}>;
endobject