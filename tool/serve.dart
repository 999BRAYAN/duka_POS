// Local static server for the release web build: COOP/COEP headers (needed
// by the OPFS-backed database), gzip, and caching. Started by serve.bat.
// ignore_for_file: avoid_print

import 'dart:io';

const _types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript',
  '.mjs': 'application/javascript',
  '.wasm': 'application/wasm',
  '.json': 'application/json',
  '.css': 'text/css',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.bin': 'application/octet-stream',
  '.frag': 'application/octet-stream',
};

Future<void> main(List<String> args) async {
  final root = Directory(args[0]).absolute.path;
  final port = args.length > 1 ? int.parse(args[1]) : 8080;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  server.autoCompress = true;
  print('Duka POS v1 at http://localhost:$port');

  await for (final req in server) {
    final res = req.response;
    res.headers
      ..set('Cross-Origin-Opener-Policy', 'same-origin')
      ..set('Cross-Origin-Embedder-Policy', 'require-corp');
    var path = Uri.decodeComponent(req.uri.path);
    if (path == '/') path = '/index.html';
    var file = File('$root${path.replaceAll('/', Platform.pathSeparator)}');
    if (path.contains('..') || !await file.exists()) {
      file = File('$root${Platform.pathSeparator}index.html');
      path = '/index.html';
    }
    final ext = path.contains('.') ? path.substring(path.lastIndexOf('.')) : '';
    res.headers.set('Content-Type', _types[ext] ?? 'application/octet-stream');
    const noCache = {'/index.html', '/flutter_service_worker.js', '/version.json', '/flutter_bootstrap.js'};
    res.headers.set('Cache-Control', noCache.contains(path) ? 'no-cache' : 'public, max-age=86400');
    if (req.method == 'HEAD') {
      res.contentLength = await file.length();
      await res.close();
    } else {
      await res.addStream(file.openRead());
      await res.close();
    }
  }
}
