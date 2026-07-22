object SERVER_OPTIONS [
  import_export_id -> "server_options"
]
  name: "Server Options"
  owner: ARCH_WIZARD
  readable: true

  property bg_ticks (owner: ARCH_WIZARD, flags: "r") = 10000000;
  property fg_ticks (owner: ARCH_WIZARD, flags: "r") = 20000000;
endobject
