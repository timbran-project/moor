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

//! In-process host/runtime service adapters for the single-process server.

#[path = "local_client.rs"]
mod local_client;
#[path = "local_events.rs"]
mod local_events;
#[path = "local_services.rs"]
mod local_services;

pub use local_client::LocalRuntimeClient;
pub use local_events::LocalEventBus;
pub use local_services::{LocalRuntimeServices, LocalWorkerServices};
