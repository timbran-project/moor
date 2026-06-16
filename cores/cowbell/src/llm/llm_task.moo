object LLM_TASK
  name: "LLM Task"
  parent: ROOT
  owner: HACKER
  fertile: true
  readable: true

  property agent (owner: HACKER, flags: "rc") = #-1;
  property completed_at (owner: HACKER, flags: "rc") = 0;
  property created_at (owner: HACKER, flags: "rc") = 0;
  property error (owner: HACKER, flags: "rc") = "";
  property knowledge_base (owner: HACKER, flags: "rc") = #-1;
  property parent_task_id (owner: HACKER, flags: "rc") = 0;
  property result (owner: HACKER, flags: "rc") = "";
  property started_at (owner: HACKER, flags: "rc") = 0;
  property status (owner: HACKER, flags: "rc") = 'pending;
  property subtasks (owner: HACKER, flags: "rc") = {};
  property task_id (owner: HACKER, flags: "rc") = 0;

  override description = "Anonymous task spawned by an LLM agent to track work and findings.";
  override import_export_hierarchy = {"llm"};
  override import_export_id = "llm_task";

  method mk owner: ARCH_WIZARD
    "Create a task (typically called by agent). Returns task object.";
    {task_id, description, ?agent = #-1, ?knowledge_base = #-1, ?parent_task_id = 0} = args;
    typeof(task_id) == TYPE_INT || raise(E_TYPE);
    typeof(description) == TYPE_STR || raise(E_TYPE);
    this.task_id = task_id;
    this.description = description;
    this.agent = agent;
    this.knowledge_base = knowledge_base;
    this.parent_task_id = parent_task_id;
    this.created_at = time();
    this.status = 'pending;
    return this;
  endmethod

  method get_status owner: ARCH_WIZARD
    "Return complete task status as a map for reporting.";
    caller == this || caller == this.agent || caller_perms().wizard || caller_perms() == this.owner || raise(E_PERM);
    status_map = ["task_id" -> this.task_id, "description" -> this.description, "status" -> this.status, "parent_task_id" -> this.parent_task_id, "created_at" -> this.created_at, "started_at" -> this.started_at, "completed_at" -> this.completed_at, "result" -> this.result, "error" -> this.error, "subtask_count" -> length(this.subtasks)];
    return status_map;
  endmethod

  method mark_in_progress owner: ARCH_WIZARD
    "Mark task as started.";
    caller == this.agent || caller_perms().wizard || caller_perms() == this.owner || raise(E_PERM);
    this.status = 'in_progress;
    this.started_at = time();
  endmethod

  method mark_complete owner: ARCH_WIZARD
    "Mark task as completed with result.";
    caller == this.agent || caller_perms().wizard || caller_perms() == this.owner || raise(E_PERM);
    {result} = args;
    this.status = 'completed;
    this.result = result;
    this.completed_at = time();
  endmethod

  method mark_failed owner: ARCH_WIZARD
    "Mark task as failed with error message.";
    caller == this.agent || caller_perms().wizard || caller_perms() == this.owner || raise(E_PERM);
    {error_msg} = args;
    this.status = 'failed;
    this.error = error_msg;
    this.completed_at = time();
  endmethod

  method mark_blocked owner: ARCH_WIZARD
    "Mark task as blocked with reason.";
    caller == this.agent || caller_perms().wizard || caller_perms() == this.owner || raise(E_PERM);
    {reason} = args;
    this.status = 'blocked;
    this.error = reason;
  endmethod

  method add_finding owner: ARCH_WIZARD
    "Add a finding to the knowledge base. Stores (task_id, subject, key, value) tuple.";
    caller == this.agent || caller_perms().wizard || caller_perms() == this.owner || raise(E_PERM);
    {subject, key, value} = args;
    typeof(subject) == TYPE_STR || raise(E_TYPE);
    typeof(key) == TYPE_STR || raise(E_TYPE);
    valid(this.knowledge_base) || raise(E_INVARG, "Knowledge base not available for this task");
    this.knowledge_base:assert({this.task_id, subject, key, value});
    return true;
  endmethod

  method get_findings owner: ARCH_WIZARD
    "Query findings by subject from knowledge base. Returns tuples matching this task.";
    caller == this.agent || caller_perms().wizard || caller_perms() == this.owner || raise(E_PERM);
    {subject} = args;
    typeof(subject) == TYPE_STR || raise(E_TYPE);
    !valid(this.knowledge_base) && return {};
    results = this.knowledge_base:select_containing(subject);
    filtered = {};
    for tuple in (results)
      length(tuple) >= 2 && tuple[2] == subject && tuple[1] == this.task_id && (filtered = {@filtered, tuple});
    endfor
    return filtered;
  endmethod

  method add_subtask owner: ARCH_WIZARD
    "Create and register a subtask. Returns the new task object.";
    caller == this.agent || caller_perms().wizard || caller_perms() == this.owner || raise(E_PERM);
    {description} = args;
    typeof(description) == TYPE_STR || raise(E_TYPE);
    valid(this.agent) || raise(E_INVARG, "Parent task's agent is invalid");
    subtask = this.agent:create_task(description, this.task_id);
    this.subtasks = {@this.subtasks, subtask};
    return subtask;
  endmethod

  method test_task_lifecycle owner: HACKER
    "Test basic task creation and status tracking.";
    kb = $relation:create(true);
    agent = $llm_agent:create(true);
    task = this:create(true);
    task:mk(1, "Test task", agent, kb, 0);
    "Check initial state";
    status = task:get_status();
    status["task_id"] != 1 && raise(E_ASSERT, "Task ID mismatch");
    status["status"] != 'pending && raise(E_ASSERT, "Should start as pending");
    "Mark in progress";
    task:mark_in_progress();
    status = task:get_status();
    status["status"] != 'in_progress && raise(E_ASSERT, "Should be in_progress");
    task.started_at == 0 && raise(E_ASSERT, "started_at should be set");
    "Mark complete";
    task:mark_complete("Success!");
    status = task:get_status();
    status["status"] != 'completed && raise(E_ASSERT, "Should be completed");
    status["result"] != "Success!" && raise(E_ASSERT, "Result mismatch");
    task.completed_at == 0 && raise(E_ASSERT, "completed_at should be set");
    "Task will auto-garbage-collect as it's anonymous";
    return true;
  endmethod

  method test_findings owner: HACKER
    "Test adding and retrieving findings with provenance.";
    kb = $relation:create(true);
    agent = $llm_agent:create(true);
    task = this:create(true);
    task:mk(1, "Test task", agent, kb, 0);
    "Add some findings";
    task:add_finding("database", "tables", {"users", "posts", "comments"});
    task:add_finding("api", "endpoints", {"/users", "/posts"});
    "Retrieve findings by subject";
    db_findings = task:get_findings("database");
    length(db_findings) != 1 && raise(E_ASSERT, "Should have 1 database finding");
    api_findings = task:get_findings("api");
    length(api_findings) != 1 && raise(E_ASSERT, "Should have 1 api finding");
    "Verify provenance is in the tuple";
    db_tuple = db_findings[1];
    db_tuple[1] != task.task_id && raise(E_ASSERT, "Provenance task_id mismatch");
    db_tuple[2] != "database" && raise(E_ASSERT, "Subject mismatch");
    "Task will auto-garbage-collect as it's anonymous";
    return true;
  endmethod
endobject
