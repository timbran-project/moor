object HEADLESS_CAPABILITY_SCENARIOS
  name: "Headless Capability Runtime Scenarios"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Headless runtime scenarios for capability issuance, grants, merges, revocation, and denial paths.";
  override import_export_hierarchy = {"tests", "headless"};
  override import_export_id = "headless_capability_scenarios";

  verb _test_key (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the deterministic PASETO key used by capability scenarios.";
    return "dGVzdHRlc3R0ZXN0dGVzdHRlc3R0ZXN0dGVzdHRlc3Q=";
  endverb

  verb test_headless_capability_issue_and_deny (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: issued capabilities validate granted permissions and deny invalid requests.";
    key = this:_test_key();
    target = #-1;
    try
      target = create($thing);
      cap = target:issue_capability(target, {'read, 'write}, 0, 0, key);
      $test_utils:assert_type(cap, TYPE_FLYWEIGHT, "issued capability should be a flyweight");
      $test_utils:assert_eq(cap.delegate, target, "issued capability delegate should match target");
      $test_utils:assert_true(maphaskey(flyslots(cap), 'token), "issued capability should include a token slot");
      {validated_target, run_as} = cap:challenge_for_with_key({'read}, key);
      $test_utils:assert_eq(validated_target, target, "challenge should return the capability target");
      $test_utils:assert_eq(run_as, $hacker, "plain capability should run as $hacker");
      missing_denied = false;
      try
        cap:challenge_for_with_key({'delete}, key);
      except (E_PERM)
        missing_denied = true;
      endtry
      $test_utils:assert_true(missing_denied, "missing permission should be denied");
      expired_cap = target:issue_capability(target, {'read}, time() - 1, 0, key);
      expired_denied = false;
      try
        expired_cap:challenge_for_with_key({'read}, key);
      except (E_PERM)
        expired_denied = true;
      endtry
      $test_utils:assert_true(expired_denied, "expired capability should be denied");
    finally
      valid(target) && target:destroy();
    endtry
    return true;
  endverb

  verb test_headless_capability_grant_merge_and_revoke (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: stored grants merge capabilities, can be found, and can be revoked.";
    key = this:_test_key();
    test_area = #-1;
    test_room = #-1;
    test_player = #-1;
    try
      test_area = create($area);
      test_room = create($room);
      test_player = create($player);
      area_cap = $root:grant_capability(test_area, {'add_room}, test_player, 'area, key);
      $test_utils:assert_type(area_cap, TYPE_FLYWEIGHT, "grant should return a capability flyweight");
      $test_utils:assert_eq(area_cap.delegate, test_area, "area grant delegate should match target");
      $test_utils:assert_eq(test_player:find_capability_for(test_area, 'area), area_cap, "stored area grant should be discoverable");
      $root:grant_capability(test_area, {'create_passage}, test_player, 'area, key);
      merged_cap = test_player:find_capability_for(test_area, 'area);
      {merged_target, _} = merged_cap:challenge_for_with_key({'add_room, 'create_passage}, key);
      $test_utils:assert_eq(merged_target, test_area, "merged grant should validate both area permissions");
      room_cap = $root:grant_capability(test_room, {'dig_from}, test_player, 'room, key);
      $test_utils:assert_eq(test_player:find_capability_for(test_room, 'room), room_cap, "room grant should be stored separately");
      $test_utils:assert_true($root:revoke_capability(test_area, test_player, 'area), "revoke should remove an existing grant");
      $test_utils:assert_false(test_player:find_capability_for(test_area, 'area), "revoked area grant should not be found");
      $test_utils:assert_false($root:revoke_capability(test_area, test_player, 'area), "revoking a missing grant should return false");
      $test_utils:assert_eq(test_player:find_capability_for(test_room, 'room), room_cap, "revoking area grant should not affect room grants");
    finally
      valid(test_player) && test_player:destroy();
      valid(test_room) && test_room:destroy();
      valid(test_area) && test_area:destroy();
    endtry
    return true;
  endverb

  verb test_headless_capability_grant_allows_non_owner_operation (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: a non-owner with a stored area capability can exercise the granted operation.";
    key = this:_test_key();
    test_area = #-1;
    new_room = #-1;
    try
      test_area = create($area);
      $root:grant_capability(test_area, {'add_room}, $player, 'area, key);
      new_room = this:_make_room_with_area_grant_as_player(test_area);
      $test_utils:assert_true(valid(new_room), "granted non-owner operation should create a room");
      $test_utils:assert_eq(new_room.location, test_area, "granted room should be added to the target area");
      $test_utils:assert_eq(new_room.owner, $player, "granted room should be owned by the grantee");
    finally
      valid(new_room) && new_room:destroy();
      valid(test_area) && test_area:destroy();
    endtry
    return true;
  endverb

  verb test_headless_capability_revoke_denies_stored_grant_operation (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: revoking a stored grant prevents later lookup-mediated use by the grantee.";
    key = this:_test_key();
    test_area = #-1;
    created = #-1;
    try
      test_area = create($area);
      $root:grant_capability(test_area, {'add_room}, $player, 'area, key);
      $test_utils:assert_true($root:revoke_capability(test_area, $player, 'area), "revoke should remove the stored area grant");
      denied = false;
      try
        created = this:_make_room_with_area_grant_as_player(test_area);
      except (E_PERM)
        denied = true;
      endtry
      $test_utils:assert_true(denied, "revoked stored grant should not authorize area room creation");
      $test_utils:assert_false($player:find_capability_for(test_area, 'area), "revoked grant should not be discoverable");
    finally
      valid(created) && created:destroy();
      valid(test_area) && test_area:destroy();
    endtry
    return true;
  endverb

  verb test_headless_capability_revoke_denies_copied_bearer_token (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Security challenge: a revoked grant should not leave a copied bearer token usable.";
    key = this:_test_key();
    test_area = #-1;
    try
      test_area = create($area);
      copied_cap = $root:grant_capability(test_area, {'add_room}, $player, 'area, key);
      $test_utils:assert_true($root:revoke_capability(test_area, $player, 'area), "revoke should remove the stored area grant");
      denied = false;
      try
        copied_cap:challenge_for_with_key({'add_room}, key);
      except (E_PERM)
        denied = true;
      endtry
      $test_utils:assert_true(denied, "revoked copied bearer token should be denied");
    finally
      valid(test_area) && test_area:destroy();
    endtry
    return true;
  endverb

  verb test_headless_capability_make_player_requires_capability (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Security challenge: a non-owner helper must not create players through the wizard-owned make_player wrapper.";
    created = #-1;
    denied = false;
    wrong_error = 0;
    before_players = players();
    try
      try
        created = this:_call_make_player_as_player();
      except e (ANY)
        if (e[1] == E_PERM)
          denied = true;
        else
          wrong_error = e[1];
        endif
      endtry
      $test_utils:assert_true(denied, "non-owner make_player wrapper call should be denied without capability");
      $test_utils:assert_false(wrong_error, "non-owner make_player should deny before reaching setup work, got " + toliteral(wrong_error));
      $test_utils:assert_eq(players(), before_players, "denied make_player should not add a player");
    finally
      if (valid(created))
        set_player_flag(created, 0);
        recycle(created);
      endif
    endtry
    return true;
  endverb

  verb test_headless_capability_merge_rejects_wrong_target (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: merging capabilities for different targets is denied.";
    key = this:_test_key();
    target_a = #-1;
    target_b = #-1;
    try
      target_a = create($thing);
      target_b = create($thing);
      cap_a = target_a:issue_capability(target_a, {'read}, 0, 0, key);
      cap_b = target_b:issue_capability(target_b, {'write}, 0, 0, key);
      wrong_target_denied = false;
      try
        $root:merge_capability(cap_a, cap_b, key);
      except (E_INVARG)
        wrong_target_denied = true;
      endtry
      $test_utils:assert_true(wrong_target_denied, "wrong-target merge should be rejected");
    finally
      valid(target_b) && target_b:destroy();
      valid(target_a) && target_a:destroy();
    endtry
    return true;
  endverb

  verb _make_room_with_area_grant_as_player (this none this) owner: PLAYER flags: "rxd"
    "Use PLAYER's stored area grant to create a room in target_area.";
    {target_area} = args;
    cap = $player:find_capability_for(target_area, 'area);
    typeof(cap) == TYPE_FLYWEIGHT || raise(E_PERM);
    return cap:make_room_in($room);
  endverb

  verb _call_make_player_as_player (this none this) owner: PLAYER flags: "rxd"
    "Attempt player creation through a non-owner player-owned helper.";
    cap = $player:make_player();
    return cap.delegate;
  endverb
endobject
