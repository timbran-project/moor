object SYSOBJ [
  import_export_id -> "sysobj"
]
  name: "System Object"
  parent: ROOT
  owner: WIZARD
  readable: true

  method do_login_command owner: WIZARD
    return #3;
  endmethod
endobject
