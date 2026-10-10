object #96
  name: "Editor_Owner"
  parent: BUILDER
  owner: #96
  player: true

  override aliases (owner: #2, flags: "r") = {"Editor_Owner"};
  override description (owner: #96, flags: "rc") = "This player owns all editor-related verbs.";
  override features (owner: HACKER, flags: "r") = {PASTING_FEATURE, STAGE_TALK};
  override home (owner: #96, flags: "rc") = #-1;
  override last_disconnect_time (owner: #2, flags: "r") = 2147483647;
  override mail_forward (owner: #96, flags: "rc") = {#2};
  override object_size (owner: HACKER, flags: "r") = {2277, 1084848672};
  override owned_objects (owner: #2, flags: "r") = {NOTE_EDITOR, VERB_EDITOR, GENERIC_EDITOR, LIST_EDITOR, #96};
  override ownership_quota (owner: HACKER, flags: "") = -10000;
  override size_quota (owner: HACKER, flags: "") = {0, -6548, 0, 0};
endobject
