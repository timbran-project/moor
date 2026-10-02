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

use super::*;
use std::time::Duration;
use tokio::sync::mpsc;
use webrtc::data_channel::data_channel_init::RTCDataChannelInit;

struct Pair {
    client: Arc<RTCPeerConnection>,
    peer: WebRtcPeer,
    received: mpsc::UnboundedReceiver<bytes::Bytes>,
}

impl Pair {
    async fn new(options: RTCDataChannelInit) -> Self {
        let client = Arc::new(
            APIBuilder::new()
                .build()
                .new_peer_connection(RTCConfiguration::default())
                .await
                .unwrap(),
        );
        let expected_ordered = options.ordered.unwrap_or(true);
        let expected_retransmits = options.max_retransmits;
        let expected_lifetime = options.max_packet_life_time;
        let channel = client
            .create_data_channel("realtime", Some(options))
            .await
            .unwrap();
        let (messages, received) = mpsc::unbounded_channel();
        channel.on_message(Box::new(move |message| {
            assert!(!message.is_string);
            let _ = messages.send(message.data);
            Box::pin(async {})
        }));
        let offer = client.create_offer(None).await.unwrap();
        let mut gathered = client.gathering_complete_promise().await;
        client.set_local_description(offer).await.unwrap();
        gathered.recv().await;
        let offer = client.local_description().await.unwrap();
        let (peer, _) = WebRtcPeer::new(
            &WebRtcConfig {
                enabled: true,
                ice_servers: vec![],
                ..Default::default()
            },
            &offer.sdp,
        )
        .await
        .unwrap();
        let mut gathered = peer.peer_connection.gathering_complete_promise().await;
        gathered.recv().await;
        let answer = peer.peer_connection.local_description().await.unwrap();
        client.set_remote_description(answer).await.unwrap();
        while !peer.is_open() {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
        let remote = peer.data_channel.lock().await.clone().unwrap();
        assert_eq!(remote.ordered(), expected_ordered);
        assert_eq!(remote.max_retransmits(), expected_retransmits);
        assert_eq!(remote.max_packet_lifetime(), expected_lifetime);
        Self {
            client,
            peer,
            received,
        }
    }
}

impl Drop for Pair {
    fn drop(&mut self) {
        let client = self.client.clone();
        tokio::spawn(async move {
            client.close().await.unwrap();
        });
    }
}

#[tokio::test]
async fn ordered_delivery_and_explicit_shutdown() {
    tokio::time::timeout(Duration::from_secs(15), async {
        let mut pair = Pair::new(RTCDataChannelInit::default()).await;
        for sequence in 0..32 {
            pair.peer.send(&[sequence]).await.unwrap();
        }
        for sequence in 0..32 {
            assert_eq!(&pair.received.recv().await.unwrap()[..], &[sequence]);
        }
        pair.peer.close().await;
        assert_eq!(
            pair.peer.peer_connection.connection_state(),
            RTCPeerConnectionState::Closed
        );
        assert!(pair.peer.send(b"after close").await.is_err());
    })
    .await
    .expect("ordered delivery and shutdown timed out");
}

#[tokio::test]
async fn incoming_unordered_channel_preserves_zero_retransmits() {
    tokio::time::timeout(Duration::from_secs(15), async {
        let mut pair = Pair::new(RTCDataChannelInit {
            ordered: Some(false),
            max_retransmits: Some(0),
            ..Default::default()
        })
        .await;
        pair.peer.send(b"realtime event").await.unwrap();
        assert_eq!(&pair.received.recv().await.unwrap()[..], b"realtime event");
        let pc = pair.peer.peer_connection.clone();
        drop(pair);
        while pc.connection_state() != RTCPeerConnectionState::Closed {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .expect("unordered delivery and drop shutdown timed out");
}

#[tokio::test]
async fn incoming_channel_preserves_finite_retransmits() {
    tokio::time::timeout(Duration::from_secs(15), async {
        let mut pair = Pair::new(RTCDataChannelInit {
            ordered: Some(false),
            max_retransmits: Some(3),
            ..Default::default()
        })
        .await;
        pair.peer.send(b"limited retries").await.unwrap();
        assert_eq!(&pair.received.recv().await.unwrap()[..], b"limited retries");
        pair.peer.close().await;
    })
    .await
    .expect("finite retransmit channel timed out");
}

#[tokio::test]
async fn incoming_channel_preserves_packet_lifetime() {
    tokio::time::timeout(Duration::from_secs(15), async {
        let mut pair = Pair::new(RTCDataChannelInit {
            ordered: Some(false),
            max_packet_life_time: Some(100),
            ..Default::default()
        })
        .await;
        pair.peer.send(b"short lived event").await.unwrap();
        assert_eq!(
            &pair.received.recv().await.unwrap()[..],
            b"short lived event"
        );
        pair.peer.close().await;
    })
    .await
    .expect("packet lifetime channel timed out");
}
