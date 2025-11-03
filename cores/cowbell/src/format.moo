object FORMAT
  name: "Format Objects"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  property block (owner: HACKER, flags: "r") = FORMAT_BLOCK;
  property list (owner: HACKER, flags: "r") = FORMAT_LIST;
  property table (owner: HACKER, flags: "r") = FORMAT_TABLE;
  property title (owner: HACKER, flags: "r") = FORMAT_TITLE;

  override description = "Container for formatting objects like block, list, table, and title.";
  override import_export_id = "format";
endobject
