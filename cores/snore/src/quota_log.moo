object QUOTA_LOG [
  import_export_id -> "quota_log"
]
  name: "Quota-Log"
  parent: MAIL_RECIPIENT
  location: MAIL_AGENT
  owner: #2

  override aliases (owner: HACKER, flags: "r") = {"Quota-Log", "Quota_Log", "QL", "Quota"};
  override description (owner: #2, flags: "rc") = "Record of whose quota has been messed with and why.";
  override mail_forward (owner: HACKER, flags: "r") = {};
  override mail_notify (owner: HACKER, flags: "r") = {#2};
  override moderated (owner: #2, flags: "rc") = 1;
  override object_size (owner: HACKER, flags: "r") = {1113, 1084848672};

  method init_for_core owner: #2
    "Reset this object for an extracted core. Wizard callers only.";
    if (caller_perms().wizard)
      pass(@args);
      this.mail_notify = {player};
      player:set_current_message(this, 0, 0, 1);
      this.moderated = 1;
    else
      raise(E_PERM);
    endif
  endmethod
endobject
