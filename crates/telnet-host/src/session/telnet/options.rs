// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// Affero General Public License as published by the Free Software Foundation,
// version 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
// details.
//
// You should have received a copy of the GNU Affero General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

//! Per-option negotiation state, following the Q method of RFC 1143.
//!
//! Each option has two independent sides: `us` (do we perform it, negotiated with WILL/WONT from
//! us and DO/DONT from the peer) and `him` (does the peer perform it, DO/DONT from us and
//! WILL/WONT from the peer). Every transition answers at most one verb, and a verb that only
//! confirms the current state produces no reply, so two conforming peers cannot loop.

use super::event::Verb;

/// Which side of an option a request or a state refers to.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
pub enum Side {
    /// We perform the option (WILL/WONT from us).
    Us,
    /// The peer performs the option (DO/DONT from us).
    Him,
}

/// The queue bit of RFC 1143's WANTNO / WANTYES states.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Default)]
pub enum Queue {
    #[default]
    Empty,
    Opposite,
}

/// The state of one side of one option.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Default)]
pub enum QState {
    #[default]
    No,
    Yes,
    WantNo(Queue),
    WantYes(Queue),
}

/// What we let one side of an option become.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Default)]
pub enum Allow {
    /// Refuse the peer and never ask.
    #[default]
    Never,
    /// Refuse when the peer asks first, but allow local requests (ECHO, SGA).
    Request,
    /// Agree when the peer asks, and allow local requests.
    Accept,
}

/// Policy for one option.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Default)]
pub struct OptionPolicy {
    pub us: Allow,
    pub him: Allow,
}

impl OptionPolicy {
    pub fn side(&self, side: Side) -> Allow {
        match side {
            Side::Us => self.us,
            Side::Him => self.him,
        }
    }
}

/// Policy for every option number.
#[derive(Clone, Debug)]
pub struct Policy {
    table: [OptionPolicy; 256],
}

impl Default for Policy {
    fn default() -> Self {
        Self {
            table: [OptionPolicy::default(); 256],
        }
    }
}

impl Policy {
    pub fn set(&mut self, option: u8, side: Side, allow: Allow) {
        let entry = &mut self.table[option as usize];
        match side {
            Side::Us => entry.us = allow,
            Side::Him => entry.him = allow,
        }
    }

    pub fn get(&self, option: u8) -> OptionPolicy {
        self.table[option as usize]
    }

    /// True when either side of the option is anything but `Never`.
    pub fn implements(&self, option: u8) -> bool {
        let p = self.get(option);
        p.us != Allow::Never || p.him != Allow::Never
    }
}

/// Result of one negotiation step.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Default)]
pub struct Outcome {
    /// The verb to send to the peer, if any.
    pub send: Option<Verb>,
    /// `Some(enabled)` when the effective state (the side being `Yes`) changed.
    pub changed: Option<bool>,
}

/// Negotiation state for all 256 options.
#[derive(Clone, Debug)]
pub struct OptionTable {
    policy: Policy,
    us: [QState; 256],
    him: [QState; 256],
}

impl OptionTable {
    pub fn new(policy: Policy) -> Self {
        Self {
            policy,
            us: [QState::No; 256],
            him: [QState::No; 256],
        }
    }

    pub fn policy(&self) -> &Policy {
        &self.policy
    }

    pub fn state(&self, option: u8, side: Side) -> QState {
        match side {
            Side::Us => self.us[option as usize],
            Side::Him => self.him[option as usize],
        }
    }

    pub fn is_enabled(&self, option: u8, side: Side) -> bool {
        self.state(option, side) == QState::Yes
    }

    fn slot(&mut self, option: u8, side: Side) -> &mut QState {
        match side {
            Side::Us => &mut self.us[option as usize],
            Side::Him => &mut self.him[option as usize],
        }
    }

    /// Apply a verb received from the peer.
    pub fn receive(&mut self, verb: Verb, option: u8) -> Outcome {
        let (side, enable) = match verb {
            Verb::Will => (Side::Him, true),
            Verb::Wont => (Side::Him, false),
            Verb::Do => (Side::Us, true),
            Verb::Dont => (Side::Us, false),
        };
        let agree = self.policy.get(option).side(side) == Allow::Accept;
        let before = self.state(option, side);
        let (after, send) = if enable {
            receive_enable(before, agree)
        } else {
            receive_disable(before)
        };
        *self.slot(option, side) = after;
        Outcome {
            send: send.map(|positive| verb_for(side, positive)),
            changed: effective_change(before, after),
        }
    }

    /// Ask to enable or disable one side of an option. A request the policy forbids, or one
    /// that matches the current or pending state, sends nothing.
    pub fn request(&mut self, option: u8, side: Side, enable: bool) -> Outcome {
        if enable && self.policy.get(option).side(side) == Allow::Never {
            return Outcome::default();
        }
        let before = self.state(option, side);
        let (after, send) = if enable {
            request_enable(before)
        } else {
            request_disable(before)
        };
        *self.slot(option, side) = after;
        Outcome {
            send: send.map(|positive| verb_for(side, positive)),
            changed: effective_change(before, after),
        }
    }
}

/// The verb we send for `side`: positive is WILL (us) / DO (him).
fn verb_for(side: Side, positive: bool) -> Verb {
    match (side, positive) {
        (Side::Us, true) => Verb::Will,
        (Side::Us, false) => Verb::Wont,
        (Side::Him, true) => Verb::Do,
        (Side::Him, false) => Verb::Dont,
    }
}

fn effective_change(before: QState, after: QState) -> Option<bool> {
    let (was, is) = (before == QState::Yes, after == QState::Yes);
    (was != is).then_some(is)
}

// The four transition functions below return the new state and `Some(positive)` when a verb
// must be sent. They are RFC 1143 section 7, line for line.

fn receive_enable(state: QState, agree: bool) -> (QState, Option<bool>) {
    match state {
        QState::No if agree => (QState::Yes, Some(true)),
        QState::No => (QState::No, Some(false)),
        QState::Yes => (QState::Yes, None),
        // The peer answered our disable with an enable: an error in the peer.
        QState::WantNo(Queue::Empty) => (QState::No, None),
        QState::WantNo(Queue::Opposite) => (QState::Yes, None),
        QState::WantYes(Queue::Empty) => (QState::Yes, None),
        QState::WantYes(Queue::Opposite) => (QState::WantNo(Queue::Empty), Some(false)),
    }
}

fn receive_disable(state: QState) -> (QState, Option<bool>) {
    match state {
        QState::No => (QState::No, None),
        QState::Yes => (QState::No, Some(false)),
        QState::WantNo(Queue::Empty) => (QState::No, None),
        QState::WantNo(Queue::Opposite) => (QState::WantYes(Queue::Empty), Some(true)),
        QState::WantYes(_) => (QState::No, None),
    }
}

fn request_enable(state: QState) -> (QState, Option<bool>) {
    match state {
        QState::No => (QState::WantYes(Queue::Empty), Some(true)),
        QState::WantNo(Queue::Empty) => (QState::WantNo(Queue::Opposite), None),
        QState::WantYes(Queue::Opposite) => (QState::WantYes(Queue::Empty), None),
        other => (other, None),
    }
}

fn request_disable(state: QState) -> (QState, Option<bool>) {
    match state {
        QState::Yes => (QState::WantNo(Queue::Empty), Some(false)),
        QState::WantNo(Queue::Opposite) => (QState::WantNo(Queue::Empty), None),
        QState::WantYes(Queue::Empty) => (QState::WantYes(Queue::Opposite), None),
        other => (other, None),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const OPT: u8 = 99;
    const ALL_STATES: [QState; 6] = [
        QState::No,
        QState::Yes,
        QState::WantNo(Queue::Empty),
        QState::WantNo(Queue::Opposite),
        QState::WantYes(Queue::Empty),
        QState::WantYes(Queue::Opposite),
    ];

    fn table(us: Allow, him: Allow) -> OptionTable {
        let mut policy = Policy::default();
        policy.set(OPT, Side::Us, us);
        policy.set(OPT, Side::Him, him);
        OptionTable::new(policy)
    }

    fn with_state(mut t: OptionTable, side: Side, state: QState) -> OptionTable {
        *t.slot(OPT, side) = state;
        t
    }

    fn sides() -> [(Side, Verb, Verb, Verb, Verb); 2] {
        // (side, peer-enable, peer-disable, our-enable, our-disable)
        [
            (Side::Him, Verb::Will, Verb::Wont, Verb::Do, Verb::Dont),
            (Side::Us, Verb::Do, Verb::Dont, Verb::Will, Verb::Wont),
        ]
    }

    #[test]
    fn receive_enable_table() {
        for (side, peer_on, _, on, off) in sides() {
            let expect = [
                (QState::No, QState::Yes, Some(on)),
                (QState::Yes, QState::Yes, None),
                (QState::WantNo(Queue::Empty), QState::No, None),
                (QState::WantNo(Queue::Opposite), QState::Yes, None),
                (QState::WantYes(Queue::Empty), QState::Yes, None),
                (
                    QState::WantYes(Queue::Opposite),
                    QState::WantNo(Queue::Empty),
                    Some(off),
                ),
            ];
            for (from, to, send) in expect {
                let mut t = with_state(table(Allow::Accept, Allow::Accept), side, from);
                let out = t.receive(peer_on, OPT);
                assert_eq!(t.state(OPT, side), to, "{side:?} {from:?} recv {peer_on:?}");
                assert_eq!(out.send, send, "{side:?} {from:?} recv {peer_on:?}");
            }
        }
    }

    #[test]
    fn receive_disable_table() {
        for (side, _, peer_off, on, off) in sides() {
            let expect = [
                (QState::No, QState::No, None),
                (QState::Yes, QState::No, Some(off)),
                (QState::WantNo(Queue::Empty), QState::No, None),
                (
                    QState::WantNo(Queue::Opposite),
                    QState::WantYes(Queue::Empty),
                    Some(on),
                ),
                (QState::WantYes(Queue::Empty), QState::No, None),
                (QState::WantYes(Queue::Opposite), QState::No, None),
            ];
            for (from, to, send) in expect {
                let mut t = with_state(table(Allow::Accept, Allow::Accept), side, from);
                let out = t.receive(peer_off, OPT);
                assert_eq!(
                    t.state(OPT, side),
                    to,
                    "{side:?} {from:?} recv {peer_off:?}"
                );
                assert_eq!(out.send, send, "{side:?} {from:?} recv {peer_off:?}");
            }
        }
    }

    #[test]
    fn request_enable_table() {
        for (side, _, _, on, _) in sides() {
            let expect = [
                (QState::No, QState::WantYes(Queue::Empty), Some(on)),
                (QState::Yes, QState::Yes, None),
                (
                    QState::WantNo(Queue::Empty),
                    QState::WantNo(Queue::Opposite),
                    None,
                ),
                (
                    QState::WantNo(Queue::Opposite),
                    QState::WantNo(Queue::Opposite),
                    None,
                ),
                (
                    QState::WantYes(Queue::Empty),
                    QState::WantYes(Queue::Empty),
                    None,
                ),
                (
                    QState::WantYes(Queue::Opposite),
                    QState::WantYes(Queue::Empty),
                    None,
                ),
            ];
            for (from, to, send) in expect {
                let mut t = with_state(table(Allow::Accept, Allow::Accept), side, from);
                let out = t.request(OPT, side, true);
                assert_eq!(t.state(OPT, side), to, "{side:?} {from:?} request on");
                assert_eq!(out.send, send, "{side:?} {from:?} request on");
                assert_eq!(out.changed, None);
            }
        }
    }

    #[test]
    fn request_disable_table() {
        for (side, _, _, _, off) in sides() {
            let expect = [
                (QState::No, QState::No, None),
                (QState::Yes, QState::WantNo(Queue::Empty), Some(off)),
                (
                    QState::WantNo(Queue::Empty),
                    QState::WantNo(Queue::Empty),
                    None,
                ),
                (
                    QState::WantNo(Queue::Opposite),
                    QState::WantNo(Queue::Empty),
                    None,
                ),
                (
                    QState::WantYes(Queue::Empty),
                    QState::WantYes(Queue::Opposite),
                    None,
                ),
                (
                    QState::WantYes(Queue::Opposite),
                    QState::WantYes(Queue::Opposite),
                    None,
                ),
            ];
            for (from, to, send) in expect {
                let mut t = with_state(table(Allow::Accept, Allow::Accept), side, from);
                let out = t.request(OPT, side, false);
                assert_eq!(t.state(OPT, side), to, "{side:?} {from:?} request off");
                assert_eq!(out.send, send, "{side:?} {from:?} request off");
                let expect_change = (from == QState::Yes).then_some(false);
                assert_eq!(out.changed, expect_change);
            }
        }
    }

    #[test]
    fn effective_change_reported_only_on_yes_boundary() {
        for (side, peer_on, peer_off, _, _) in sides() {
            for from in ALL_STATES {
                for verb in [peer_on, peer_off] {
                    let mut t = with_state(table(Allow::Accept, Allow::Accept), side, from);
                    let out = t.receive(verb, OPT);
                    let after = t.state(OPT, side);
                    let expect = ((from == QState::Yes) != (after == QState::Yes))
                        .then_some(after == QState::Yes);
                    assert_eq!(out.changed, expect, "{side:?} {from:?} {verb:?}");
                }
            }
        }
    }

    #[test]
    fn refuses_disallowed_options() {
        for allow in [Allow::Never, Allow::Request] {
            let mut t = table(allow, allow);
            let out = t.receive(Verb::Will, OPT);
            assert_eq!(out.send, Some(Verb::Dont));
            assert_eq!(t.state(OPT, Side::Him), QState::No);
            let out = t.receive(Verb::Do, OPT);
            assert_eq!(out.send, Some(Verb::Wont));
            assert_eq!(t.state(OPT, Side::Us), QState::No);
            // Disable verbs for an option already off are not answered.
            assert_eq!(t.receive(Verb::Wont, OPT), Outcome::default());
            assert_eq!(t.receive(Verb::Dont, OPT), Outcome::default());
        }
    }

    #[test]
    fn request_respects_policy() {
        let mut t = table(Allow::Never, Allow::Never);
        assert_eq!(t.request(OPT, Side::Us, true), Outcome::default());
        assert_eq!(t.request(OPT, Side::Him, true), Outcome::default());

        let mut t = table(Allow::Request, Allow::Never);
        let out = t.request(OPT, Side::Us, true);
        assert_eq!(out.send, Some(Verb::Will));
        // Our own request is answered with DO and accepted though unsolicited DO would not be.
        let out = t.receive(Verb::Do, OPT);
        assert_eq!(out.send, None);
        assert_eq!(out.changed, Some(true));
    }

    #[test]
    fn opposite_queue_enable_then_disable_during_negotiation() {
        let mut t = table(Allow::Accept, Allow::Accept);
        assert_eq!(t.request(OPT, Side::Him, true).send, Some(Verb::Do));
        // Change of mind while the DO is outstanding: queued, nothing sent.
        assert_eq!(t.request(OPT, Side::Him, false).send, None);
        assert_eq!(t.state(OPT, Side::Him), QState::WantYes(Queue::Opposite));
        // Peer agrees to the DO: we now immediately send the queued DONT.
        let out = t.receive(Verb::Will, OPT);
        assert_eq!(out.send, Some(Verb::Dont));
        assert_eq!(out.changed, None);
        assert_eq!(t.state(OPT, Side::Him), QState::WantNo(Queue::Empty));
        let out = t.receive(Verb::Wont, OPT);
        assert_eq!(out, Outcome::default());
        assert_eq!(t.state(OPT, Side::Him), QState::No);
    }

    #[test]
    fn opposite_queue_disable_then_enable_during_negotiation() {
        let mut t = with_state(table(Allow::Accept, Allow::Accept), Side::Us, QState::Yes);
        assert_eq!(t.request(OPT, Side::Us, false).send, Some(Verb::Wont));
        assert_eq!(t.request(OPT, Side::Us, true).send, None);
        assert_eq!(t.state(OPT, Side::Us), QState::WantNo(Queue::Opposite));
        let out = t.receive(Verb::Dont, OPT);
        assert_eq!(out.send, Some(Verb::Will));
        assert_eq!(t.state(OPT, Side::Us), QState::WantYes(Queue::Empty));
        let out = t.receive(Verb::Do, OPT);
        assert_eq!(out.send, None);
        assert_eq!(out.changed, Some(true));
    }

    #[test]
    fn requests_are_idempotent() {
        let mut t = table(Allow::Accept, Allow::Accept);
        assert_eq!(t.request(OPT, Side::Us, true).send, Some(Verb::Will));
        for _ in 0..5 {
            assert_eq!(t.request(OPT, Side::Us, true), Outcome::default());
        }
        t.receive(Verb::Do, OPT);
        for _ in 0..5 {
            assert_eq!(t.request(OPT, Side::Us, true), Outcome::default());
        }
        assert_eq!(t.request(OPT, Side::Us, false).send, Some(Verb::Wont));
        t.receive(Verb::Dont, OPT);
        for _ in 0..5 {
            assert_eq!(t.request(OPT, Side::Us, false), Outcome::default());
        }
    }

    /// Deliver verbs between two tables until neither has anything to send. `a_first` are
    /// verbs from `a` to `b`, `b_first` from `b` to `a`; both are in flight at once, the way
    /// two ends offering at connect cross on the wire.
    fn pump(
        a: &mut OptionTable,
        b: &mut OptionTable,
        a_first: Vec<Verb>,
        b_first: Vec<Verb>,
    ) -> usize {
        let mut in_flight: std::collections::VecDeque<(bool, Verb)> = a_first
            .into_iter()
            .map(|v| (true, v))
            .chain(b_first.into_iter().map(|v| (false, v)))
            .collect();
        let mut messages = 0;
        while let Some((to_b, verb)) = in_flight.pop_front() {
            messages += 1;
            assert!(messages < 100, "negotiation did not converge");
            let target = if to_b { &mut *b } else { &mut *a };
            if let Some(reply) = target.receive(verb, OPT).send {
                in_flight.push_back((!to_b, reply));
            }
        }
        messages
    }

    #[test]
    fn back_to_back_tables_reach_fixed_point() {
        for (a_allow, b_allow) in [
            (Allow::Accept, Allow::Accept),
            (Allow::Accept, Allow::Never),
            (Allow::Never, Allow::Accept),
        ] {
            let mut a = table(a_allow, a_allow);
            let mut b = table(b_allow, b_allow);
            // Both ends ask for everything at once, the classic loop trigger.
            let mut a_first = Vec::new();
            for side in [Side::Us, Side::Him] {
                if let Some(v) = a.request(OPT, side, true).send {
                    a_first.push(v);
                }
            }
            let mut b_first = Vec::new();
            for side in [Side::Us, Side::Him] {
                if let Some(v) = b.request(OPT, side, true).send {
                    b_first.push(v);
                }
            }
            pump(&mut a, &mut b, a_first, b_first);
            // Fixed point: nothing pending on either end.
            for t in [&a, &b] {
                for side in [Side::Us, Side::Him] {
                    let s = t.state(OPT, side);
                    assert!(matches!(s, QState::Yes | QState::No), "{s:?}");
                }
            }
            let both = a_allow == Allow::Accept && b_allow == Allow::Accept;
            assert_eq!(a.is_enabled(OPT, Side::Us), both);
            assert_eq!(b.is_enabled(OPT, Side::Him), both);
            // Toggle off and on repeatedly and confirm termination each time.
            for enable in [false, true, false] {
                let first: Vec<_> = a.request(OPT, Side::Us, enable).send.into_iter().collect();
                pump(&mut a, &mut b, first, Vec::new());
                assert_eq!(a.is_enabled(OPT, Side::Us), enable && both);
                assert_eq!(b.is_enabled(OPT, Side::Him), enable && both);
            }
        }
    }
}
