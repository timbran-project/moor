object PLAN_FAILURES [
  import_export_id -> "plan_failures",
  import_export_hierarchy -> {"rules"}
]
  name: "Plan Failures"
  parent: RELATION
  owner: ARCH_WIZARD
  readable: true

  override fact_schema (owner: HACKER, flags: "rc") = ['columns -> {'actor, 'goal, 'approach, 'choice}, 'types -> ['actor -> 'object, 'goal -> 'symbol, 'approach -> 'symbol, 'choice -> 'string]];
  override set_version (owner: HACKER, flags: "rc") = 1;
  override description (owner: HACKER, flags: "rc") = "Approaches that recently failed for an NPC, with the matches they used. Facts expire, so an NPC tries again later.";
endobject
