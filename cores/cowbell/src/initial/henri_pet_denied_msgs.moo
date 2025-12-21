object HENRI_PET_DENIED_MSGS
  name: "Henri Pet Denied Messages"
  parent: MSG_BAG
  owner: HACKER
  readable: true

  override entries = {
    "{nc} hisses and swats at {p_dobj} hand before {dobj} can touch him.",
    "{nc} lets out a low growl and bares {p} teeth at {dobj}.",
    "{nc} backs away with a suspicious glare, clearly warning {dobj} to keep {p} distance.",
    "{nc} flexes {p} claws menacingly as {dobj} approaches, a silent but clear threat."
  };
  override import_export_hierarchy = {"initial"};
  override import_export_id = "henri_pet_denied_msgs";
endobject