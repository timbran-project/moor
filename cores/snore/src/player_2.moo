object #2
  name: "Wizard"
  parent: WIZ
  location: PLAYER_START
  owner: #2
  player: true
  wizard: true
  programmer: true

  override aliases (owner: #2, flags: "rc") = {"Wizard"};
  override current_folder (owner: #2, flags: "c") = #2;
  override current_message (owner: #2, flags: "c") = {
    0,
    0,
    {NEW_PLAYER_LOG, 0, 0},
    {NEW_PROG_LOG, 0, 0},
    {QUOTA_LOG, 0, 0},
    {NEWT_LOG, 0, 0}
  };
  override features (owner: HACKER, flags: "r") = {
    PASTING_FEATURE,
    STAGE_TALK,
    UTILITY_FEATURE,
    BUILDER_FEATURE,
    PROGRAMMER_FEATURE,
    WIZARD_FEATURE
  };
  override first_connect_time (owner: #2, flags: "r") = 1529444339;
  override last_connect_place (owner: #2, flags: "") = "";
  override last_connect_time (owner: #2, flags: "r") = 1529543480;
  override last_disconnect_time (owner: #2, flags: "r") = 1529543472;
  override object_size (owner: HACKER, flags: "r") = {5052, 1084848672};
  override owned_objects (owner: #2, flags: "r") = {
    SYSOBJ,
    ROOT_CLASS,
    #2,
    ROOM,
    BUILDER,
    THING,
    PLAYER,
    EXIT,
    CONTAINER,
    NOTE,
    LOGIN,
    LAST_HUH,
    GUEST_LOG,
    LIMBO,
    NEW_PLAYER_LOG,
    STRING_UTILS,
    BUILDING_UTILS,
    WIZ_UTILS,
    NEW_PROG_LOG,
    QUOTA_LOG,
    MAIL_RECIPIENT_CLASS,
    PERM_UTILS,
    OBJECT_UTILS,
    LOCK_UTILS,
    LETTER,
    COMMAND_UTILS,
    WIZ,
    PROG,
    NEWT_LOG,
    GENERIC_UTILS,
    SERVER_OPTIONS,
    PASSWORD_VERIFIER,
    GENDERED_OBJECT
  };
  override ownership_quota (owner: HACKER, flags: "") = -10000;
  override password (owner: #2, flags: "") = 0;
  override previous_connection (owner: #2, flags: "") = {1529444339, "localhost"};
  override size_quota (owner: HACKER, flags: "") = {50000, 769725, 1084848672, 0};
endobject
