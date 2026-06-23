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

//! Runtime-facing typed APIs and local in-process implementations.

mod api;
mod local_client;
mod local_events;
mod services;

pub use api::RuntimeApi;
pub use local_client::LocalRuntimeClient;
pub use local_events::{
    LocalClientBroadcastSubscription, LocalClientEventSubscription, LocalEventBus,
    LocalHostEventSubscription,
};
pub use services::LocalRuntimeServices;
