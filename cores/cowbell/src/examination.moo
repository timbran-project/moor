object EXAMINATION
  name: "Object Examination Flyweight Delegate"
  parent: ROOT
  owner: HACKER

  override description = "The $examination flyweight delegate serves as the delegate for examination flyweights that hold structured metadata about objects. Contains slots for: object_ref, name, aliases, owner, parent, description, verbs (obvious ones only), location, contents. Objects override :examination() to provide their own metadata. This object provides utility verbs for working with examination flyweights.";
  override import_export_id = "examination";

  verb validate (this none this) owner: HACKER flags: "rxd"
    "Check if this is a valid examination flyweight.";
    if (typeof(this) != FLYWEIGHT)
      return false;
    endif
    try
      this.object_ref && this.name && this.verbs && return true;
    except (E_PROPNF)
      return false;
    endtry
    return true;
  endverb
endobject