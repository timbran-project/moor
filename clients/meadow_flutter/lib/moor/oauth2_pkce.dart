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

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class PkcePair {
  final String codeVerifier;
  final String codeChallenge;
  final String codeChallengeMethod;

  const PkcePair({
    required this.codeVerifier,
    required this.codeChallenge,
    this.codeChallengeMethod = 'S256',
  });
}

Future<PkcePair> generatePkcePair() async {
  final rnd = Random.secure();
  final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
  final verifier = _base64UrlNoPad(bytes);

  final digest = await Sha256().hash(utf8.encode(verifier));
  final challenge = _base64UrlNoPad(digest.bytes);

  return PkcePair(
    codeVerifier: verifier,
    codeChallenge: challenge,
  );
}

String _base64UrlNoPad(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}
