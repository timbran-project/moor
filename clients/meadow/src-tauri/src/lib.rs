// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// General Public License as published by the Free Software Foundation, version
// 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <https://www.gnu.org/licenses/>.
//

use std::sync::Mutex;
use tauri::State;

struct ServerUrl(Mutex<String>);

#[tauri::command]
fn get_server_url(state: State<ServerUrl>) -> String {
    state.0.lock().unwrap().clone()
}

fn parse_server_url() -> String {
    let args: Vec<String> = std::env::args().collect();
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--server" | "-s" => {
                if i + 1 < args.len() {
                    return args[i + 1].trim_end_matches('/').to_string();
                }
            }
            _ => {
                if let Some(url) = args[i].strip_prefix("--server=") {
                    return url.trim_end_matches('/').to_string();
                }
            }
        }
        i += 1;
    }
    String::new()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let server_url = parse_server_url();
    if !server_url.is_empty() {
        eprintln!("Server URL: {}", server_url);
    }

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_cors_fetch::init())
        .manage(ServerUrl(Mutex::new(server_url)))
        .invoke_handler(tauri::generate_handler![get_server_url])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
