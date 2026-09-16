String webOriginServer(Uri page) {
  if (page.host.isEmpty) {
    return '';
  }
  return page.origin;
}
