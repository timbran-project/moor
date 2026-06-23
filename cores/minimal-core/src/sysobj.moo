object SYSOBJ
  name: "System Object"
  parent: ROOT
  owner: WIZARD
  readable: true

  override import_export_id = "sysobj";

  method do_login_command owner: WIZARD
    return #3;
  endmethod
endobject
