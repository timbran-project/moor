object DVAR
  name: "Datalog Variable"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for datalog query variables used in relation pattern matching.";
  override import_export_id = "dvar";

  verb "mk_*" (this none this) owner: HACKER flags: "rxd"
    "Create a datalog variable: $dvar:mk_room() returns <$dvar, {'room}>";
    var_name = verb[4..length(verb)];
    return <this, {tosym(var_name)}>;
  endverb

  verb name (this none this) owner: HACKER flags: "rxd"
    "Return the variable name symbol from this dvar flyweight";
    return flycontents(this)[1];
  endverb
endobject