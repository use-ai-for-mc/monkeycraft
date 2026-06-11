/// True if [data] contains an IDR NAL unit (type 5) behind a 3-byte or
/// 4-byte Annex-B start code.
bool containsIdrNal(List<int> data) {
  for (int i = 0; i + 3 < data.length; i++) {
    if (data[i] != 0 || data[i + 1] != 0) continue;
    int nalStart;
    if (data[i + 2] == 1) {
      nalStart = i + 3;
    } else if (data[i + 2] == 0 && i + 4 < data.length && data[i + 3] == 1) {
      nalStart = i + 4;
    } else {
      continue;
    }
    if ((data[nalStart] & 0x1F) == 5) return true;
    i = nalStart - 1;
  }
  return false;
}
