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

import 'package:flutter/foundation.dart';

import 'package:meadow_flutter/moor/http_api.dart';
import 'package:meadow_flutter/moor/types/moor_coll.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';

typedef ProfileStatusLogger = void Function(String message);

@immutable
class ProfilePictureData {
  final String contentType;
  final Uint8List data;

  const ProfilePictureData({
    required this.contentType,
    required this.data,
  });
}

class AccountProfileController extends ChangeNotifier {
  final MoorHttpApi _api;

  bool _loaded = false;
  bool _loading = false;
  bool _saving = false;
  ProfilePictureData? _profilePicture;
  String? _playerDescription;
  String? _currentPronouns;
  List<String> _availablePronounPresets = const <String>[];
  bool _pronounsAvailable = false;

  AccountProfileController({
    required MoorHttpApi api,
  }) : _api = api;

  bool get loaded => _loaded;
  bool get loading => _loading;
  bool get saving => _saving;
  ProfilePictureData? get profilePicture => _profilePicture;
  String? get playerDescription => _playerDescription;
  String? get currentPronouns => _currentPronouns;
  List<String> get availablePronounPresets => _availablePronounPresets;
  bool get pronounsAvailable => _pronounsAvailable;

  Future<void> load({
    required String authToken,
    required String playerCurie,
    required ProfileStatusLogger onStatus,
    bool force = false,
  }) async {
    if (_loading) {
      return;
    }
    if (_loaded && !force) {
      return;
    }
    _loading = true;
    notifyListeners();

    try {
      final results = await Future.wait<Object?>(<Future<Object?>>[
        _fetchProfilePicture(authToken: authToken, playerCurie: playerCurie),
        _fetchPlayerDescription(authToken: authToken, playerCurie: playerCurie),
        _fetchCurrentPronouns(authToken: authToken, playerCurie: playerCurie),
        _fetchPronounPresets(authToken: authToken),
      ]);

      _profilePicture = results[0] as ProfilePictureData?;
      _playerDescription = results[1] as String?;
      _currentPronouns = results[2] as String?;
      final presets = results[3];
      _availablePronounPresets = presets is List<String>
          ? presets
          : const <String>[];
      _pronounsAvailable =
          _currentPronouns != null || _availablePronounPresets.isNotEmpty;
      _loaded = true;
    } on Object catch (e) {
      onStatus('Account profile refresh failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> updateDescription({
    required String authToken,
    required String playerCurie,
    required String description,
    required ProfileStatusLogger onStatus,
  }) async {
    return _runSave(
      onStatus: onStatus,
      action: () async {
        await _api.invokeVerb(
          authToken: authToken,
          objectCurie: playerCurie,
          verbName: 'set_description',
          argsVarBytes: Uint8List.fromList(
            MoorList(<MoorVar>[
              MoorVar(description),
            ]).toVar().toBytes(),
          ),
        );
        _playerDescription = description;
      },
      successMessage: description.trim().isEmpty
          ? 'Profile description cleared'
          : 'Profile description updated',
      failurePrefix: 'Profile description update failed',
    );
  }

  Future<bool> updatePronouns({
    required String authToken,
    required String playerCurie,
    required String pronouns,
    required ProfileStatusLogger onStatus,
  }) async {
    return _runSave(
      onStatus: onStatus,
      action: () async {
        await _api.invokeVerb(
          authToken: authToken,
          objectCurie: playerCurie,
          verbName: 'set_pronouns',
          argsVarBytes: Uint8List.fromList(
            MoorList(<MoorVar>[
              MoorVar(pronouns),
            ]).toVar().toBytes(),
          ),
        );
        _currentPronouns = pronouns;
        _pronounsAvailable = true;
      },
      successMessage: 'Pronouns updated',
      failurePrefix: 'Pronouns update failed',
    );
  }

  Future<bool> uploadProfilePicture({
    required String authToken,
    required String playerCurie,
    required String contentType,
    required Uint8List data,
    required ProfileStatusLogger onStatus,
  }) async {
    return _runSave(
      onStatus: onStatus,
      action: () async {
        await _api.invokeVerb(
          authToken: authToken,
          objectCurie: playerCurie,
          verbName: 'set_profile_picture',
          argsVarBytes: Uint8List.fromList(
            MoorList(
              <MoorVar>[
                MoorVar(contentType),
                MoorVar(data),
              ],
            ).toVar().toBytes(),
          ),
        );
        _profilePicture = ProfilePictureData(
          contentType: contentType,
          data: data,
        );
      },
      successMessage: 'Profile picture updated',
      failurePrefix: 'Profile picture update failed',
    );
  }

  Future<ProfilePictureData?> _fetchProfilePicture({
    required String authToken,
    required String playerCurie,
  }) async {
    try {
      final success = await _api.invokeVerb(
        authToken: authToken,
        objectCurie: playerCurie,
        verbName: 'profile_picture',
      );
      final result = success.result;
      if (result == null) {
        return null;
      }
      final value = MoorVar.fromFlatBuffer(result).value;
      if (value is! MoorList || value.elements.length < 2) {
        return null;
      }
      final contentType = value.elements.first.asString();
      final data = value.elements[1].asBinary();
      if (contentType == null || data == null || data.isEmpty) {
        return null;
      }
      return ProfilePictureData(
        contentType: contentType,
        data: data,
      );
    } on Object {
      return null;
    }
  }

  Future<String?> _fetchPlayerDescription({
    required String authToken,
    required String playerCurie,
  }) async {
    try {
      final success = await _api.invokeVerb(
        authToken: authToken,
        objectCurie: playerCurie,
        verbName: 'description',
      );
      final result = success.result;
      if (result == null) {
        return null;
      }
      final description = MoorVar.fromFlatBuffer(result).asString();
      return description == null || description.trim().isEmpty
          ? null
          : description;
    } on Object {
      return null;
    }
  }

  Future<String?> _fetchCurrentPronouns({
    required String authToken,
    required String playerCurie,
  }) async {
    try {
      final success = await _api.invokeVerb(
        authToken: authToken,
        objectCurie: playerCurie,
        verbName: 'pronouns_display',
      );
      final result = success.result;
      if (result == null) {
        return null;
      }
      final pronouns = MoorVar.fromFlatBuffer(result).asString();
      return pronouns == null || pronouns.trim().isEmpty ? null : pronouns;
    } on Object {
      return null;
    }
  }

  Future<List<String>> _fetchPronounPresets({
    required String authToken,
  }) async {
    try {
      final success = await _api.invokeVerb(
        authToken: authToken,
        objectCurie: 'sysobj:pronouns',
        verbName: 'list_presets',
      );
      final result = success.result;
      if (result == null) {
        return const <String>[];
      }
      final value = MoorVar.fromFlatBuffer(result).value;
      if (value is! MoorList) {
        return const <String>[];
      }
      return value.elements
          .map((element) => element.asString()?.trim())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    } on Object {
      return const <String>[];
    }
  }

  Future<bool> _runSave({
    required ProfileStatusLogger onStatus,
    required Future<void> Function() action,
    required String successMessage,
    required String failurePrefix,
  }) async {
    _saving = true;
    notifyListeners();
    try {
      await action();
      onStatus(successMessage);
      return true;
    } on Object catch (e) {
      onStatus('$failurePrefix: $e');
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
