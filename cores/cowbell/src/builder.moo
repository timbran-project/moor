object BUILDER
  name: "Generic Builder"
  parent: PLAYER
  location: FIRST_ROOM
  owner: HACKER
  fertile: true
  readable: true

  override description = "Generic builder character prototype. Builders can create and modify basic objects and rooms. Inherits from player with building permissions.";
  override import_export_id = "builder";
endobject