object NEWT_LOG [
  import_export_id -> "newt_log"
]
  name: "Site-Locks"
  parent: MAIL_RECIPIENT
  location: MAIL_AGENT
  owner: #2

  override aliases (owner: HACKER, flags: "r") = {"Site-Locks"};
  override description (owner: #2, flags: "rc") = "Notes on annoying sites.";
  override mail_forward (owner: HACKER, flags: "r") = {};
  override mail_notify (owner: HACKER, flags: "r") = {#2};
  override moderated (owner: #2, flags: "rc") = 1;
  override object_size (owner: HACKER, flags: "r") = {1042, 1084848672};

  method init_for_core owner: #2
    "Reset this object for an extracted core. Wizard callers only.";
    if (caller_perms().wizard)
      pass(@args);
      this.mail_notify = {player};
      player:set_current_message(this, 0, 0, 1);
      this.moderated = 1;
    else
      return E_PERM;
    endif
  endmethod
endobject
