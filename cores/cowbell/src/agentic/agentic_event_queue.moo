object AGENTIC_EVENT_QUEUE
  name: "Agentic Event Queue"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  property queue (owner: ARCH_WIZARD, flags: "rc") = {};

  override description = "Queue helper for agentic runners and observers.";
  override import_export_hierarchy = {"agentic"};
  override import_export_id = "agentic_event_queue";

  verb push (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Append an item to queue.";
    {item} = args;
    this.queue = {@this.queue, item};
    return length(this.queue);
  endverb

  verb pop (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Pop first item from queue. Returns false when empty.";
    length(this.queue) == 0 && return 0;
    item = this.queue[1];
    this.queue = length(this.queue) > 1 ? (this.queue)[2..$] | {};
    return item;
  endverb

  verb size (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return queue length.";
    return length(this.queue);
  endverb

  verb clear (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Clear queue.";
    this.queue = {};
    return 1;
  endverb
endobject