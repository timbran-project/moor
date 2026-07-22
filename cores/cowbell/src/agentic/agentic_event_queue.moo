object AGENTIC_EVENT_QUEUE [
  import_export_id -> "agentic_event_queue",
  import_export_hierarchy -> {"agentic"}
]
  name: "Agentic Event Queue"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  property queue (owner: ARCH_WIZARD, flags: "rc") = {};

  override description = "Queue helper for agentic runners and observers.";

  method push owner: ARCH_WIZARD
    "Append an item to queue.";
    {item} = args;
    this.queue = {@this.queue, item};
    return length(this.queue);
  endmethod

  method pop owner: ARCH_WIZARD
    "Pop first item from queue. Returns false when empty.";
    length(this.queue) == 0 && return 0;
    item = this.queue[1];
    this.queue = length(this.queue) > 1 ? this.queue[2..$] | {};
    return item;
  endmethod

  method size owner: ARCH_WIZARD
    "Return queue length.";
    return length(this.queue);
  endmethod

  method clear owner: ARCH_WIZARD
    "Clear queue.";
    this.queue = {};
    return 1;
  endmethod
endobject
