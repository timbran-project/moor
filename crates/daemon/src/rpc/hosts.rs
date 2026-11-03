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

use moor_runtime_api::ListenerKind;
use moor_var::Obj;
use std::{collections::HashMap, net::SocketAddr, time::SystemTime};
use tracing::warn;
use uuid::Uuid;

/// Manages the set of known hosts and the listeners they have registered.
struct HostRecord {
    last_seen: SystemTime,
    listener_kinds: Vec<ListenerKind>,
    listeners: Vec<(Obj, ListenerKind, SocketAddr)>,
}

#[derive(Default)]
pub struct Hosts(HashMap<Uuid, HostRecord>);

impl Hosts {
    pub(crate) fn receive_ping(
        &mut self,
        host_id: Uuid,
        listener_kinds: Vec<ListenerKind>,
        listeners: Vec<(Obj, ListenerKind, SocketAddr)>,
    ) -> bool {
        let now = SystemTime::now();
        self.0
            .insert(
                host_id,
                HostRecord {
                    last_seen: now,
                    listener_kinds,
                    listeners,
                },
            )
            .is_none()
    }

    pub(crate) fn ping_check(&mut self, timeout: std::time::Duration) {
        let now = SystemTime::now();
        let mut expired = vec![];
        for (host_id, HostRecord { last_seen, .. }) in self.0.iter() {
            if now.duration_since(*last_seen).unwrap() > timeout {
                warn!(
                    "Host {} has not responded in time: {:?}, removing its listeners from the list",
                    host_id,
                    now.duration_since(*last_seen).unwrap()
                );
                expired.push(*host_id);
            }
        }
        for host_id in expired {
            self.unregister_host(&host_id);
        }
    }

    pub(crate) fn listeners(&self) -> Vec<(Obj, ListenerKind, SocketAddr)> {
        self.0
            .values()
            .flat_map(|HostRecord { listeners, .. }| listeners.iter().copied())
            .collect()
    }

    /// Whether any registered host can open listeners of this kind.
    pub(crate) fn offers(&self, kind: ListenerKind) -> bool {
        self.0
            .values()
            .any(|HostRecord { listener_kinds, .. }| listener_kinds.contains(&kind))
    }

    pub(crate) fn len(&self) -> usize {
        self.0.len()
    }

    pub(crate) fn unregister_host(&mut self, host_id: &Uuid) {
        self.0.remove(host_id);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_var::SYSTEM_OBJECT;

    #[test]
    fn listeners_keep_their_kinds_across_hosts() {
        let quic = ListenerKind::parse("webtransport").unwrap();
        let mut hosts = Hosts::default();
        hosts.receive_ping(
            Uuid::new_v4(),
            vec![ListenerKind::TELNET],
            vec![(
                SYSTEM_OBJECT,
                ListenerKind::TELNET,
                "0.0.0.0:7777".parse().unwrap(),
            )],
        );
        hosts.receive_ping(
            Uuid::new_v4(),
            vec![ListenerKind::HTTP, quic],
            vec![
                (
                    SYSTEM_OBJECT,
                    ListenerKind::HTTP,
                    "0.0.0.0:8080".parse().unwrap(),
                ),
                (Obj::mk_id(5), quic, "0.0.0.0:4433".parse().unwrap()),
            ],
        );

        let mut listeners = hosts.listeners();
        listeners.sort_by_key(|(_, _, addr)| addr.port());
        assert_eq!(
            listeners
                .iter()
                .map(|(obj, kind, addr)| (*obj, kind.id_str(), addr.port()))
                .collect::<Vec<_>>(),
            vec![
                (Obj::mk_id(5), "webtransport", 4433),
                (SYSTEM_OBJECT, "telnet", 7777),
                (SYSTEM_OBJECT, "http", 8080),
            ]
        );
        assert!(hosts.offers(quic));
        assert!(!hosts.offers(ListenerKind::parse("minecraft").unwrap()));
    }
}
