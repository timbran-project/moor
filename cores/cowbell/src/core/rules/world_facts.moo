object WORLD_FACTS [
  import_export_id -> "world_facts",
  import_export_hierarchy -> {"rules"}
]
  name: "World Facts"
  parent: ROOT
  owner: HACKER
  readable: true

  method schemas owner: HACKER
    "Declare the read-only world predicates and their named inputs and outputs.";
    return ['is -> ['description -> "Compare two exact values.", 'label -> "{left} is {right}", 'inputs -> ['left -> 'any, 'right -> 'any], 'outputs -> []], 'isa -> ['description -> "Check an object's prototype ancestry.", 'label -> "{object} is a kind of {prototype}", 'inputs -> ['object -> 'object, 'prototype -> 'object], 'outputs -> []], 'owner_is -> ['description -> "Check an object's owner.", 'label -> "{owner} owns {object}", 'inputs -> ['object -> 'object, 'owner -> 'object], 'outputs -> []], 'location_is -> ['description -> "Check an object's location.", 'label -> "{object} is in {location}", 'inputs -> ['object -> 'object, 'location -> 'object], 'outputs -> []], 'nearby -> ['description -> "Check whether an object is at a supplied location.", 'label -> "{object} is at {location}", 'inputs -> ['object -> 'object, 'location -> 'object], 'outputs -> []], 'contains -> ['description -> "Check whether a container directly contains an item.", 'label -> "{container} holds {item}", 'inputs -> ['container -> 'object, 'item -> 'object], 'outputs -> []], 'is_wizard -> ['description -> "Check an actor's wizard flag.", 'label -> "{actor} is a wizard", 'inputs -> ['actor -> 'object], 'outputs -> []], 'is_programmer -> ['description -> "Check an actor's programmer flag.", 'label -> "{actor} is a programmer", 'inputs -> ['actor -> 'object], 'outputs -> []], 'is_builder -> ['description -> "Check an actor's builder flag.", 'label -> "{actor} is a builder", 'inputs -> ['actor -> 'object], 'outputs -> []], 'is_open -> ['description -> "Check a container's open state.", 'label -> "{object} is open", 'inputs -> ['object -> 'object], 'outputs -> []], 'is_locked -> ['description -> "Check a container's locked state.", 'label -> "{object} is locked", 'inputs -> ['object -> 'object], 'outputs -> []], 'is_portable -> ['description -> "Check an item's portable state.", 'label -> "{object} can be carried", 'inputs -> ['object -> 'object], 'outputs -> []], 'sitting -> ['description -> "Check whether an actor is on a seat.", 'label -> "{actor} is sitting on {seat}", 'inputs -> ['actor -> 'object, 'seat -> 'object], 'outputs -> []], 'property_is -> ['description -> "Compare a readable property with an exact value.", 'label -> "the {field} of {object} is {value}", 'inputs -> ['object -> 'object, 'field -> 'symbol, 'value -> 'any], 'outputs -> []], 'property_at_least -> ['description -> "Compare a readable integer property with a minimum.", 'label -> "the {field} of {object} is at least {minimum}", 'inputs -> ['object -> 'object, 'field -> 'symbol, 'minimum -> 'integer], 'outputs -> []], 'within_reach -> ['description -> "Check whether an object is held by an actor or beside it.", 'label -> "{actor} can reach {object}", 'inputs -> ['actor -> 'object, 'object -> 'object], 'outputs -> []], 'wearing -> ['description -> "Check whether an actor wears an item.", 'label -> "{actor} is wearing {item}", 'inputs -> ['actor -> 'object, 'item -> 'object], 'outputs -> []], 'location_of -> ['description -> "Select an object's location.", 'label -> "where {object} is", 'inputs -> ['object -> 'object], 'outputs -> ['location -> 'object]], 'next_step -> ['description -> "Select the first exit on a route through open passages between two rooms.", 'label -> "the way from {from} to {to}", 'inputs -> ['from -> 'object, 'to -> 'object], 'outputs -> ['exit -> 'string, 'room -> 'object]], 'occupants -> ['description -> "Select direct contents of one readable location.", 'label -> "who and what is in {location}", 'inputs -> ['location -> 'object], 'outputs -> ['object -> 'object]]];
  endmethod

  method query owner: ARCH_WIZARD
    "Read a bounded world scope with the caller's permissions. No object predicate callbacks.";
    set_task_perms(caller_perms());
    const {name, values, limit} = args;
    const schema = $world_facts:schemas()[name];
    $behavior_schema:bindings(values, schema['inputs]);
    for key in (mapkeys(schema['inputs]))
      if (schema['inputs][key] == 'object)
        valid(values[key]) || raise(E_INVARG, "Invalid object argument " + tostr(key));
      endif
    endfor
    let matches = false;
    if (name == 'is)
      matches = equal(values['left], values['right]);
    elseif (name == 'isa)
      matches = isa(values['object], values['prototype]);
    elseif (name == 'owner_is)
      matches = values['object].owner == values['owner];
    elseif (name in {'location_is, 'nearby})
      matches = values['object].location == values['location];
    elseif (name == 'contains)
      matches = values['item].location == values['container];
    elseif (name in {'is_wizard, 'is_programmer, 'is_builder})
      const fields = ['is_wizard -> "wizard", 'is_programmer -> "programmer", 'is_builder -> "is_builder"];
      matches = !!values['actor].(fields[name]);
    elseif (name in {'is_open, 'is_locked, 'is_portable})
      const fields = ['is_open -> "open", 'is_locked -> "locked", 'is_portable -> "portable"];
      matches = !!values['object].(fields[name]);
    elseif (name == 'sitting)
      matches = !!(values['actor] in values['seat].sitting);
    elseif (name == 'location_of)
      return ['rows -> {['location -> values['object].location]}, 'complete -> true];
    elseif (name == 'next_step)
      const path = values['from] == values['to] ? false | $area:find_path(values['from], values['to], true, false, caller_perms());
      if (typeof(path) != TYPE_LIST || length(path) < 2)
        return ['rows -> {}, 'complete -> true];
      endif
      const {room, passage} = path[1];
      const exit = room == passage.side_a_room ? passage.side_a_label | passage.side_b_label;
      return ['rows -> {['exit -> tostr(exit), 'room -> path[2][1]]}, 'complete -> true];
    elseif (name == 'within_reach)
      matches = $container:_reachable(values['object], values['actor]);
    elseif (name == 'wearing)
      matches = !!(values['item] in `values['actor].wearing ! E_PROPNF, E_PERM => {}');
    elseif (name == 'property_is)
      matches = equal(values['object].(tostr(values['field])), values['value]);
    elseif (name == 'property_at_least)
      const value = values['object].(tostr(values['field]));
      typeof(value) == TYPE_INT || raise(E_TYPE, "Expected an integer property");
      matches = value >= values['minimum];
    elseif (name == 'occupants)
      const contents = values['location].contents;
      return ['rows -> { ['object -> item] for item in (contents[1..min(length(contents), limit)]) }, 'complete -> length(contents) <= limit];
    endif
    return ['rows -> matches ? {[]} | {}, 'complete -> true];
  endmethod
endobject
