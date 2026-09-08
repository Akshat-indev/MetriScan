/// Normalizes text for product fingerprints and pattern keys.
String normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

double similarity(String left, String right) {
  final a = normalize(left);
  final b = normalize(right);
  if (a == b) return 1.0;
  if (a.isEmpty || b.isEmpty) return 0.0;

  final aTokens = a.split(' ').toSet();
  final bTokens = b.split(' ').toSet();
  final union = {...aTokens, ...bTokens};
  final overlap = aTokens.intersection(bTokens).length;
  final tokenScore = union.isEmpty ? 0.0 : overlap / union.length;
  final distance = _levenshtein(a, b);
  final editScore = 1 - distance / (a.length > b.length ? a.length : b.length);
  final compactA = a.replaceAll(' ', '');
  final compactB = b.replaceAll(' ', '');
  final compactDistance = _levenshtein(compactA, compactB);
  final compactScore = 1 -
      compactDistance /
          (compactA.length > compactB.length
              ? compactA.length
              : compactB.length);
  return (tokenScore * 0.25) + (editScore * 0.25) + (compactScore * 0.5);
}

int _levenshtein(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (index) => index);
  for (var i = 0; i < a.length; i++) {
    final current = <int>[i + 1];
    for (var j = 0; j < b.length; j++) {
      final insert = current[j] + 1;
      final delete = previous[j + 1] + 1;
      final replace = previous[j] + (a[i] == b[j] ? 0 : 1);
      current.add([insert, delete, replace].reduce((x, y) => x < y ? x : y));
    }
    previous = current;
  }
  return previous.last;
}
