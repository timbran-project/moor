object FORMAT_ANNOTATION [
  import_export_id -> "format_annotation",
  import_export_hierarchy -> {"format"}
]
  name: "Semantic Annotation"
  parent: ROOT
  owner: HACKER
  readable: true

  method mk owner: HACKER
    "Capture a label and a descriptor; allocation of occurrence anchors happens during rendering.";
    const {label, descriptor, ?plain_label = label} = args;
    typeof(label) == TYPE_STR && typeof(plain_label) == TYPE_STR && typeof(descriptor) == TYPE_MAP || raise(E_TYPE);
    length(toliteral(descriptor)) <= 2048 || raise(E_INVARG, "Annotation descriptor is too large");
    return <this, .label = label, .plain_label = plain_label, .descriptor = descriptor>;
  endmethod

  method object owner: HACKER
    "Capture an object reference with its authored label.";
    const {target, ?label = target:name()} = args;
    return this:mk(label, ["kind" -> "object", "ref" -> $url_utils:to_curie_str(target), "objectKind" -> target:reference_kind()]);
  endmethod

  method with_action owner: HACKER
    "Attach authored action labels without changing the parser command.";
    const {action} = args;
    let descriptor = this.descriptor;
    descriptor["action"] = action;
    return <$format.annotation, .label = this.label, .plain_label = `this.plain_label ! E_PROPNF => this.label', .descriptor = descriptor, .code = `this.code ! E_PROPNF => false'>;
  endmethod

  method command owner: HACKER
    "Capture the exact single-line command for explicit review.";
    const {command, ?label = command} = args;
    return this:mk(label, ["kind" -> "command", "command" -> command], label == command ? label | tostr(label, ": ", command));
  endmethod

  method as_code owner: HACKER
    "Keep the annotation clickable while rendering its label as inline code.";
    return <$format.annotation, .label = this.label, .plain_label = `this.plain_label ! E_PROPNF => this.label', .descriptor = this.descriptor, .code = true>;
  endmethod

  method command_syntax owner: HACKER
    "Show clickable command syntax followed by its description.";
    const {command, ?label = command} = args;
    const link = this:mk(command, ["kind" -> "command", "command" -> command]):as_code();
    return label == command ? link | $format.paragraph:inline(link, " — ", label);
  endmethod

  method command_template owner: HACKER
    "Describe authored argument fields and an exact parser template for command review.";
    const {template, fields, label} = args;
    typeof(template) == TYPE_STR && typeof(fields) == TYPE_MAP && length(fields) in {1, 2} || raise(E_INVARG);
    for slot in (mapkeys(fields))
      slot in {"dobj", "iobj"} || raise(E_INVARG);
      $match:input_context(template, slot);
    endfor
    return this:mk(label, ["kind" -> "command", "template" -> template, "arguments" -> fields]);
  endmethod

  method exit owner: HACKER
    "Use the registered exit descriptor and command supplied by its room.";
    const {room, direction, ?label = direction} = args;
    const descriptor = room:exit_annotation(direction);
    return length(descriptor) ? this:mk(label, descriptor) | label;
  endmethod

  method help owner: HACKER
    "Qualify a topic by its help provider.";
    const {provider, topic, ?label = topic} = args;
    return this:mk(label, ["kind" -> "help", "provider" -> $url_utils:to_curie_str(provider), "topic" -> topic]);
  endmethod

  method verb owner: HACKER
    "Identify a verb on its receiver, optionally qualified by the definer.";
    const {receiver, name, ?label = tostr(receiver) + ":" + name, ?definer = false} = args;
    let descriptor = ["kind" -> "verb", "receiver" -> $url_utils:to_curie_str(receiver), "name" -> name];
    typeof(definer) == TYPE_OBJ && valid(definer) && (descriptor["definer"] = $url_utils:to_curie_str(definer));
    return this:mk(label, descriptor);
  endmethod

  method property owner: HACKER
    "Identify a property location, independently of its current value.";
    const {object, name, ?label = tostr(object) + "." + name} = args;
    return this:mk(label, ["kind" -> "property", "object" -> $url_utils:to_curie_str(object), "name" -> name]);
  endmethod

  method escape_djot owner: HACKER
    "Escape ASCII punctuation in captured labels, including table delimiters and attribute syntax.";
    const {label} = args;
    let escaped = "";
    for i in [1..length(label)]
      const ch = label[i];
      const punctuation = index("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~", ch);
      escaped = escaped + (punctuation ? "\\" | "") + ch;
    endfor
    return escaped;
  endmethod

  method compose owner: HACKER
    "Produce an occurrence anchor and descriptor for rich output, or just the label for telnet.";
    const {render_for, content_type, event} = args;
    content_type in {'text_html, 'text_djot} || return `this.plain_label ! E_PROPNF => this.label';
    "Each occurrence gets an independent anchor, even when the same fragment appears twice.";
    const id = "a" + uuid();
    const code = `this.code ! E_PROPNF => false';
    const label = code ? $format.code:inline(this.label):compose(render_for, content_type, event) | this.label;
    const body = content_type == 'text_html ? <$html, {"span", {"data-moor-annotation", id}, {label}}> | "[" + (code ? label | this:escape_djot(label)) + "]{annotation=" + id + "}";
    return $format:result(body, [id -> this.descriptor]);
  endmethod
endobject
