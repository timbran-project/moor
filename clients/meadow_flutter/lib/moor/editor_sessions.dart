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

sealed class EditorSession {
  final String id;
  final String title;
  final String presentationId;

  const EditorSession({
    required this.id,
    required this.title,
    required this.presentationId,
  });
}

class VerbEditorSession extends EditorSession {
  final String objectCurie;
  final String verbName;

  const VerbEditorSession({
    required super.id,
    required super.title,
    required super.presentationId,
    required this.objectCurie,
    required this.verbName,
  });
}

class PropertyEditorSession extends EditorSession {
  final String objectCurie;
  final String propertyName;
  final bool isValueEditor;

  const PropertyEditorSession({
    required super.id,
    required super.title,
    required super.presentationId,
    required this.objectCurie,
    required this.propertyName,
    required this.isValueEditor,
  });
}
