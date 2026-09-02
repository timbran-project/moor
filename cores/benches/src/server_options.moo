object SERVER_OPTIONS [
  import_export_id -> "server_options"
]
  name: "Server Options"
  owner: ARCH_WIZARD
  readable: true

  property bg_ticks (owner: ARCH_WIZARD, flags: "r") = 10000000;
  property db_commit_queue_timeout_seconds (owner: ARCH_WIZARD, flags: "r") = 5.0;
  property db_commit_queue_warn_seconds (owner: ARCH_WIZARD, flags: "r") = 1.0;
  property fg_ticks (owner: ARCH_WIZARD, flags: "r") = 20000000;
endobject
