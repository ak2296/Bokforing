import 'package:bokforing/domain/release_notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release notes are newest first with ids counting down by one', () {
    for (var i = 0; i < releaseNotes.length - 1; i++) {
      expect(releaseNotes[i].id, releaseNotes[i + 1].id + 1);
    }
    expect(latestNoteId, releaseNotes.first.id);
    expect(releaseNotes.every((n) => n.items.isNotEmpty && n.date.isNotEmpty), isTrue);
  });
}
