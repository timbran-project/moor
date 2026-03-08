// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com>
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <https://www.gnu.org/licenses/>.

class LaunchArgs {
  final String? server;
  final String? username;
  final String? password;
  final String? mode; // "connect" | "create"
  final bool login;
  final Uri? callbackUri;

  const LaunchArgs({
    required this.server,
    required this.username,
    required this.password,
    required this.mode,
    required this.login,
    required this.callbackUri,
  });
}

LaunchArgs parseLaunchArgs(List<String> args) {
  String? server;
  String? username;
  String? password;
  String? mode;
  var login = false;
  Uri? callbackUri;

  String? takeValue(String a, int i, String name) {
    final eq = a.indexOf('=');
    if (eq >= 0) {
      return a.substring(eq + 1);
    }
    if (i + 1 < args.length) {
      return args[i + 1];
    }
    return null;
  }

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) {
      final uri = Uri.tryParse(a);
      if (uri != null && uri.scheme.isNotEmpty) {
        callbackUri ??= uri;
      }
      continue;
    }
    if (a == '--login') {
      login = true;
      continue;
    }
    if (a.startsWith('--server')) {
      server = takeValue(a, i, 'server');
      if (!a.contains('=') && server != null) i++;
      continue;
    }
    if (a.startsWith('--username')) {
      username = takeValue(a, i, 'username');
      if (!a.contains('=') && username != null) i++;
      continue;
    }
    if (a.startsWith('--password')) {
      password = takeValue(a, i, 'password');
      if (!a.contains('=') && password != null) i++;
      continue;
    }
    if (a.startsWith('--mode')) {
      mode = takeValue(a, i, 'mode');
      if (!a.contains('=') && mode != null) i++;
      continue;
    }
  }

  mode = (mode == 'create' || mode == 'connect') ? mode : null;

  return LaunchArgs(
    server: server,
    username: username,
    password: password,
    mode: mode,
    login: login,
    callbackUri: callbackUri,
  );
}
