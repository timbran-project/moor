object EXAMINATION [
  import_export_id -> "examination"
]
  name: "Object Examination Flyweight Delegate"
  parent: ROOT
  owner: HACKER

  override description = "The $examination flyweight delegate serves as the delegate for examination flyweights that hold structured metadata about objects. Contains slots for: object_ref, name, aliases, owner, parent, description, verbs (obvious ones only), location, contents. Objects override :examination() to provide their own metadata. This object provides utility verbs for working with examination flyweights.";

  method validate owner: HACKER
    "Check if this is a valid examination flyweight.";
    typeof(this) == TYPE_FLYWEIGHT || return false;
    return `this.object_ref && this.name && this.verbs ! E_PROPNF => false';
  endmethod
endobject
