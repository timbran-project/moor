object HACKER [
  import_export_id -> "hacker"
]
  name: "Hacker"
  parent: PROG
  owner: HACKER
  player: true
  programmer: true
  readable: true

  override aliases (owner: #2, flags: "r") = {"Hacker"};
  override description (owner: HACKER, flags: "rc") = "A system character used to own non-wizardly system verbs , properties, and objects in the core.";
  override features (owner: HACKER, flags: "r") = {
    PASTING_FEATURE,
    STAGE_TALK,
    UTILITY_FEATURE,
    BUILDER_FEATURE,
    PROGRAMMER_FEATURE,
    WIZARD_FEATURE
  };
  override home (owner: HACKER, flags: "rc") = #-1;
  override last_disconnect_time (owner: #2, flags: "r") = 2147483647;
  override mail_forward (owner: HACKER, flags: "rc") = {#2};
  override object_size (owner: HACKER, flags: "r") = {2102, 1084848672};
  override owned_objects (owner: #2, flags: "r") = 0;
  override ownership_quota (owner: HACKER, flags: "") = 37331;
  override size_quota (owner: HACKER, flags: "") = {100000008, -27508461, 1008125633, 1510455};

  method init_for_core owner: #2
    "Reset this object for an extracted core. Wizard callers only.";
    if (caller_perms().wizard)
      pass(@args);
      this.mail_forward = {$owner};
    endif
  endmethod
endobject
