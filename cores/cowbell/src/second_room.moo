object SECOND_ROOM
  name: "The Second Room"
  parent: ROOM
  location: FIRST_AREA
  owner: ARCH_WIZARD
  readable: true

  override description = "You are in the Second Room.\nThe air smells faintly of ozone, and there is a passage back to the first room.";
  override import_export_id = "second_room";
endobject