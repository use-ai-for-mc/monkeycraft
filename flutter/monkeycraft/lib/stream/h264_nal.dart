class H264SpsInfo {
  final int profileIdc;
  final int constraintSetFlags;
  final int levelIdc;

  const H264SpsInfo({
    required this.profileIdc,
    required this.constraintSetFlags,
    required this.levelIdc,
  });

  String get codecString {
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    return 'avc1.${hex(profileIdc)}${hex(constraintSetFlags)}${hex(levelIdc)}';
  }
}

int? _nalStartAfter(List<int> data, int i) {
  if (i + 3 >= data.length) return null;
  if (data[i] != 0 || data[i + 1] != 0) return null;
  if (data[i + 2] == 1) return i + 3;
  if (data[i + 2] == 0 && i + 4 < data.length && data[i + 3] == 1) {
    return i + 4;
  }
  return null;
}

Iterable<int> annexBNalTypes(List<int> data) sync* {
  for (int i = 0; i + 3 < data.length; i++) {
    final nalStart = _nalStartAfter(data, i);
    if (nalStart == null) continue;
    yield data[nalStart] & 0x1F;
    i = nalStart - 1;
  }
}

bool containsNalType(List<int> data, int type) {
  for (final nalType in annexBNalTypes(data)) {
    if (nalType == type) return true;
  }
  return false;
}

bool containsIdrNal(List<int> data) => containsNalType(data, 5);

bool containsSpsNal(List<int> data) => containsNalType(data, 7);

bool containsPpsNal(List<int> data) => containsNalType(data, 8);

H264SpsInfo? parseSpsCodec(List<int> data) {
  for (int i = 0; i + 3 < data.length; i++) {
    final nalStart = _nalStartAfter(data, i);
    if (nalStart == null) continue;
    if ((data[nalStart] & 0x1F) == 7 && nalStart + 3 < data.length) {
      return H264SpsInfo(
        profileIdc: data[nalStart + 1],
        constraintSetFlags: data[nalStart + 2],
        levelIdc: data[nalStart + 3],
      );
    }
    i = nalStart - 1;
  }
  return null;
}
