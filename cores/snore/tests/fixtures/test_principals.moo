object TEST_PLAYER [
  import_export_id -> "test_player"
]
  name: "Test Player"
  parent: DEFAULT_PLAYER
  owner: TEST_PLAYER
  location: TEST_ROOM
  player: true
  fertile: false
  readable: true

  override aliases = {"testplayer"};
  override home = TEST_ROOM;
  override password = 0;

  property command_trace (owner: TEST_PLAYER, flags: "r") = {};

  verb "player-first" (none none none) owner: #2 flags: "rd"
    "Record that player commands precede feature commands.";
    this.command_trace = {"player"};
  endverb

  method attempt_foreign_edit owner: TEST_PLAYER
    "Attempt to edit another object with this player's permissions. Returns the error or 1.";
    {target} = args;
    result = `add_verb(target, {this, "rd", "foreign_probe"}, {"this", "none", "this"}) ! ANY';
    typeof(result) == TYPE_ERR || return result;
    result = `(target.description = {"changed by another player"}) ! ANY';
    return typeof(result) == TYPE_ERR ? result | 1;
  endmethod
endobject

object TEST_PROGRAMMER [
  import_export_id -> "test_programmer"
]
  name: "Test Programmer"
  parent: PROG
  owner: TEST_PROGRAMMER
  location: TEST_ROOM
  player: true
  programmer: true
  fertile: false
  readable: true

  override aliases = {"testprog"};
  override home = TEST_ROOM;
  override password = 0;
  method editor_access owner: TEST_PROGRAMMER
    "Invoke an operation with this programmer's permissions.";
    const {editor, operation, @parameters} = args;
    return editor:(operation)(@parameters);
  endmethod

endobject

object TEST_ROOM [
  import_export_id -> "test_room"
]
  name: "Test Chamber"
  parent: ROOM
  owner: HACKER
  fertile: false
  readable: true

  property extra_match_objects (owner: #2, flags: "r") = {};

  method match_scope_for owner: #2
    "Add test objects or custom alias entries to the inherited room scope.";
    return {@pass(@args), @this.extra_match_objects};
  endmethod

  verb "feature-first" (none none none) owner: #2 flags: "rd"
    "Record the room command when no feature overrides it.";
    player.command_trace = {"room"};
  endverb

  override description = {"A bare room used by the automated tests.", "There is nothing here."};
  override exits = {TEST_EXIT_EAST};
endobject

object TEST_ROOM_TWO [
  import_export_id -> "test_room_two"
]
  name: "Test Chamber Two"
  parent: ROOM
  owner: HACKER
  fertile: false
  readable: true

  override description = {"A second bare room used by movement tests.", "There is nothing here."};
  override exits = {TEST_EXIT_WEST};
endobject

object TEST_EXIT_EAST [
  import_export_id -> "test_exit_east"
]
  name: "east"
  parent: EXIT
  location: TEST_ROOM
  owner: HACKER
  fertile: false
  readable: true

  override aliases = {"east", "e"};
  override dest = TEST_ROOM_TWO;
  override source = TEST_ROOM;
endobject

object TEST_EXIT_WEST [
  import_export_id -> "test_exit_west"
]
  name: "west"
  parent: EXIT
  location: TEST_ROOM_TWO
  owner: HACKER
  fertile: false
  readable: true

  override aliases = {"west", "w"};
  override dest = TEST_ROOM;
  override source = TEST_ROOM_TWO;
endobject

object TEST_THING [
  import_export_id -> "test_thing"
]
  name: "baseline thing"
  parent: THING
  location: TEST_ROOM
  owner: HACKER
  fertile: false
  readable: true

  override aliases = {"thing", "baseline"};
endobject

object TEST_GAME_PLAYER [
  import_export_id -> "test_game_player"
]
  name: "Test Game Player"
  parent: TEST_GAME_CLASS
  owner: TEST_GAME_PLAYER
  location: TEST_ROOM
  player: true
  fertile: false
  readable: true

  override aliases = {"testgame"};
  override home = TEST_ROOM;
  override password = 0;
endobject

object TEST_MAILBOX [
  import_export_id -> "test_mailbox"
]
  name: "Test Mailbox"
  parent: MAIL_RECIPIENT
  location: MAIL_AGENT
  owner: HACKER
  fertile: false
  readable: true

  override aliases = {"testmailbox"};
  override mail_forward = {};
endobject

object TEST_CONTAINER [
  import_export_id -> "test_container"
]
  name: "Test Box"
  parent: CONTAINER
  location: TEST_ROOM
  owner: HACKER
  fertile: false
  readable: true

  override aliases = {"testbox"};
endobject

object TEST_GAME_CLASS [
  import_export_id -> "test_game_class"
]
  name: "game player class"
  parent: MAIL_RECIPIENT_CLASS
  owner: #2
  fertile: true
  readable: true

  override features = {PASTING_FEATURE, STAGE_TALK};
endobject
