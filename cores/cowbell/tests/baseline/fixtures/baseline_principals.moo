// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com>
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <https://www.gnu.org/licenses/>.

object RUNTIME_WIZARD
  name: "RUNTIME_WIZARD"
  parent: PLAYER
  owner: RUNTIME_WIZARD
  location: RUNTIME_ROOM
  player: true
  wizard: true
  programmer: true
  readable: true
  override import_export_id = "runtime_wizard";
  override import_export_hierarchy = {"tests", "baseline"};
  override home = RUNTIME_ROOM;
  property runtime_probe (owner: RUNTIME_WIZARD, flags: "r") = 0;
  verb permission_probe (this none this) owner: RUNTIME_WIZARD flags: "rxd"
    "Prove own writes succeed and report a protected foreign write.";
    this.runtime_probe = 1;
    const own_result = this.runtime_probe;
    const foreign_result = `(#90100.runtime_probe = 2) ! E_PERM => E_PERM';
    return {own_result, foreign_result};
  endverb
endobject

object RUNTIME_PROGRAMMER
  name: "RUNTIME_PROGRAMMER"
  parent: PLAYER
  owner: RUNTIME_PROGRAMMER
  location: RUNTIME_ROOM
  player: true
  programmer: true
  readable: true
  override import_export_id = "runtime_programmer";
  override import_export_hierarchy = {"tests", "baseline"};
  override home = RUNTIME_ROOM;
  property runtime_probe (owner: RUNTIME_PROGRAMMER, flags: "r") = 0;
  verb permission_probe (this none this) owner: RUNTIME_PROGRAMMER flags: "rxd"
    "Prove own writes succeed and report a protected foreign write.";
    this.runtime_probe = 1;
    const own_result = this.runtime_probe;
    const foreign_result = `(#90100.runtime_probe = 2) ! E_PERM => E_PERM';
    return {own_result, foreign_result};
  endverb
endobject

object RUNTIME_PLAYER
  name: "RUNTIME_PLAYER"
  parent: PLAYER
  owner: RUNTIME_PLAYER
  location: RUNTIME_ROOM
  player: true
  readable: true
  override import_export_id = "runtime_player";
  override import_export_hierarchy = {"tests", "baseline"};
  override home = RUNTIME_ROOM;
  verb "runtime-test-raise" (none none none) owner: RUNTIME_WIZARD flags: "rd"
    "Raise an uncaught error to verify command exception handling.";
    raise(E_INVARG, "cowbell harness command exception");
  endverb
  property runtime_probe (owner: RUNTIME_PLAYER, flags: "r") = 0;
  verb permission_probe (this none this) owner: RUNTIME_PLAYER flags: "rxd"
    "Prove own writes succeed and report a protected foreign write.";
    this.runtime_probe = 1;
    const own_result = this.runtime_probe;
    const foreign_result = `(#90100.runtime_probe = 2) ! E_PERM => E_PERM';
    return {own_result, foreign_result};
  endverb
  verb "runtime-test-denial" (none none none) owner: RUNTIME_PLAYER flags: "rd"
    "Emit an ordinary denial without an exception.";
    this:inform_current($event:mk_error(this, "Fixture denial"));
  endverb
endobject

object RUNTIME_ROOM
  name: "Runtime Test Chamber"
  parent: ROOM
  owner: RUNTIME_WIZARD
  readable: true
  override description = "A room for isolated Cowbell runtime tests.";
  override import_export_id = "runtime_room";
  override import_export_hierarchy = {"tests", "baseline"};
endobject

object RUNTIME_BASELINE
  name: "Runtime Baseline Scenarios"
  parent: ROOT
  owner: RUNTIME_WIZARD
  readable: true
  override import_export_id = "runtime_baseline";
  override import_export_hierarchy = {"tests", "baseline"};

  verb test_fixture_principals (this none this) owner: #90100 flags: "rxd"
    $test_utils:assert_true(#90100.wizard, "fixture wizard flag");
    $test_utils:assert_true(#90100.programmer, "wizard programmer flag");
    $test_utils:assert_false(#90101.wizard, "programmer has no wizard flag");
    $test_utils:assert_true(#90101.programmer, "fixture programmer flag");
    $test_utils:assert_false(#90102.wizard, "player has no wizard flag");
    $test_utils:assert_false(#90102.programmer, "player has no programmer flag");
    $test_utils:assert_eq(#90100:permission_probe(), {1, 2}, "wizard protected write succeeds");
    $test_utils:assert_eq(#90101:permission_probe(), {1, E_PERM}, "programmer own write succeeds and foreign write denied");
    $test_utils:assert_eq(#90102:permission_probe(), {1, E_PERM}, "player own write succeeds and foreign write denied");
    for principal in ({#90100, #90101, #90102})
      $test_utils:assert_true(is_player(principal), "fixture player flag");
      $test_utils:assert_eq(principal.owner, principal, "fixture self ownership");
      $test_utils:assert_eq(principal.location, #90103, "isolated fixture room");
    endfor
    return true;
  endverb
endobject
