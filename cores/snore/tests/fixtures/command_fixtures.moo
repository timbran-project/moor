// Command providers and matching targets for the imported test overlay.
object TEST_COMMAND_FEATURE [import_export_id -> "test_command_feature"]
  name: "Command Test Feature"
  parent: FEATURE
  owner: #2
  readable: true

  property hook_log (owner: #2, flags: "r") = {};
  property fail_hooks (owner: #2, flags: "r") = false;

  method feature_add owner: #2
    "Record list membership as observed by the post-install callback.";
    const {who} = args;
    this.hook_log = {@this.hook_log, {"add", who, !!(this in who.features)}};
    this.fail_hooks && raise(E_INVARG, "feature callback failure");
  endmethod

  method feature_remove owner: #2
    "Record list membership as observed by the post-removal callback.";
    const {who} = args;
    this.hook_log = {@this.hook_log, {"remove", who, !!(this in who.features)}};
    this.fail_hooks && raise(E_INVARG, "feature callback failure");
  endmethod

  method has_feature_verb owner: #2
    "Exercise the retained feature redirect and rejection hooks.";
    const {command, @specifications} = args;
    command == "redirect-method" && return "redirect_target";
    command == "redirect-command" && return "parserprobe";
    command == "reject-probe" && return false;
    return pass(@args);
  endmethod

  method redirect_target owner: #2
    "Public-method redirects receive the typed command arguments.";
    player.command_trace = {"redirect", args};
  endmethod

  verb "reject-probe" (none none none) owner: #2 flags: "rd"
    "The hook must prevent this verb from running through feature dispatch.";
    player.command_trace = {"unexpected rejected command"};
  endverb

  verb "parserprobe pp" (any any any) owner: #2 flags: "rd"
    "Record actual command globals, including the caller permission sentinel.";
    player.command_trace = {dobj, iobj, dobjstr, iobjstr, prepstr, argstr, args, caller_perms()};
  endverb

  verb "feature-first player-first" (none none none) owner: #2 flags: "rd"
    "Record command-environment precedence.";
    player.command_trace = {"feature"};
  endverb
endobject

object TEST_BRONZE_ORB [import_export_id -> "test_bronze_orb"]
  name: "bronze orb"
  parent: THING
  owner: #2
  readable: true
  override aliases = {"orb", "copper sphere"};

  verb activate (this none none) owner: #2 flags: "rd"
    "Only this ambiguous candidate supports activation.";
    player.command_trace = {"activated", this, dobj};
  endverb
endobject

object TEST_SILVER_ORB [import_export_id -> "test_silver_orb"]
  name: "silver orb"
  parent: THING
  owner: #2
  readable: true
  override aliases = {"orb", "silver sphere"};
endobject

object TEST_REMOTE_RUNE [import_export_id -> "test_remote_rune"]
  name: "remote rune"
  parent: THING
  owner: #2
  readable: true

  verb awaken (this none none) owner: #2 flags: "rd"
    "Record a command reached through a room's extended matching scope.";
    player.command_trace = {"awakened", this};
  endverb
endobject
