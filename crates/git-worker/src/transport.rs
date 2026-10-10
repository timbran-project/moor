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

//! Bound response bytes across the entire Git HTTP conversation, including ref advertisements.
use gix::protocol::transport::client::blocking_io::http::{self, Http};
use std::{
    io::{self, BufReader, Read},
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
};

#[derive(Clone)]
pub(crate) struct Budget {
    remaining: Arc<AtomicUsize>,
    pub exceeded: Arc<AtomicBool>,
    pub authentication_required: Arc<AtomicBool>,
}
impl Budget {
    pub fn new(bytes: usize) -> Self {
        Self {
            remaining: Arc::new(AtomicUsize::new(bytes)),
            exceeded: Arc::new(AtomicBool::new(false)),
            authentication_required: Arc::new(AtomicBool::new(false)),
        }
    }
    fn wrap<R: Read>(&self, reader: R) -> BufReader<Counted<R>> {
        BufReader::new(Counted {
            reader,
            budget: self.clone(),
        })
    }
    pub fn error(&self) -> crate::protocol::Error {
        if self.exceeded.load(Ordering::Relaxed) {
            crate::protocol::Error::new(
                "limit_exceeded",
                "Git response exceeds the fetch byte limit",
            )
        } else if self.authentication_required.load(Ordering::Relaxed) {
            crate::protocol::Error::new(
                "authentication_required",
                "Repository requires authentication",
            )
        } else {
            crate::protocol::Error::new("fetch_failed", "Git retrieval failed")
        }
    }
}
pub(crate) struct Counted<R> {
    reader: R,
    budget: Budget,
}
impl<R: Read> Read for Counted<R> {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        let length = buffer.len().min(
            self.budget
                .remaining
                .load(Ordering::Relaxed)
                .saturating_add(1),
        );
        let count = self
            .reader
            .read(&mut buffer[..length])
            .inspect_err(|error| {
                if error.kind() == io::ErrorKind::PermissionDenied {
                    self.budget
                        .authentication_required
                        .store(true, Ordering::Relaxed);
                }
            })?;
        if self
            .budget
            .remaining
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |remaining| {
                remaining.checked_sub(count)
            })
            .is_err()
        {
            self.budget.exceeded.store(true, Ordering::Relaxed);
            return Err(io::Error::other("Git fetch byte limit exceeded"));
        }
        Ok(count)
    }
}
pub(crate) struct BoundedHttp {
    inner: http::reqwest::Remote,
    budget: Budget,
}
impl BoundedHttp {
    pub fn new(budget: Budget) -> Self {
        Self {
            inner: Default::default(),
            budget,
        }
    }
}
impl Http for BoundedHttp {
    type Headers = BufReader<Counted<<http::reqwest::Remote as Http>::Headers>>;
    type ResponseBody = BufReader<Counted<<http::reqwest::Remote as Http>::ResponseBody>>;
    type PostBody = <http::reqwest::Remote as Http>::PostBody;
    fn get(
        &mut self,
        url: &str,
        base_url: &str,
        headers: impl IntoIterator<Item = impl AsRef<str>>,
    ) -> Result<http::GetResponse<Self::Headers, Self::ResponseBody>, http::Error> {
        let response = self.inner.get(url, base_url, headers)?;
        Ok(http::GetResponse {
            headers: self.budget.wrap(response.headers),
            body: self.budget.wrap(response.body),
        })
    }
    fn post(
        &mut self,
        url: &str,
        base_url: &str,
        headers: impl IntoIterator<Item = impl AsRef<str>>,
        body: http::PostBodyDataKind,
    ) -> Result<http::PostResponse<Self::Headers, Self::ResponseBody, Self::PostBody>, http::Error>
    {
        let response = self.inner.post(url, base_url, headers, body)?;
        Ok(http::PostResponse {
            headers: self.budget.wrap(response.headers),
            body: self.budget.wrap(response.body),
            post_body: response.post_body,
        })
    }
    fn configure(
        &mut self,
        config: &dyn std::any::Any,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        self.inner.configure(config)
    }
}
