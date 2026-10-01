// Hello from Dart, on Laravel Cloud's Go runtime.
//
// Laravel Cloud runs this binary because the branch carries a `go.mod` at its
// root, so the environment was detected as Go when it was created and Cloud
// starts whatever executable the build command left at `./app`. The build
// command never compiles any Go: it downloads the binary GitHub Actions built
// from this commit with `dart compile exe`.
//
// The shared template, the index URL and the OG card come in through
// bin/embedded.g.dart, which tool/embed.dart generates before the compile, so
// nothing on Cloud's ephemeral filesystem matters once the process is up.
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'embedded.g.dart';

const language = 'Dart';
const branch = 'dart';
const repoUrl = 'https://github.com/artisan-build/hello_cloud';

/// Fills the shared template's seven placeholders. `replaceAll`, not
/// `replaceFirst`: {{LANGUAGE}} appears nine times.
String page(String host) {
  final base = 'https://$host';
  return template
      .replaceAll('{{LANGUAGE}}', language)
      .replaceAll('{{BRANCH_URL}}', '$repoUrl/tree/$branch')
      .replaceAll('{{BRANCH}}', branch)
      .replaceAll('{{OG_IMAGE}}', '$base/og.png')
      .replaceAll('{{PAGE_URL}}', '$base/')
      .replaceAll('{{INDEX_URL}}', indexUrl.trim())
      .replaceAll('{{EXTRA}}', '');
}

Response handle(Request request) {
  // og:image and og:url have to be absolute, so they are built from the
  // request's Host header with a hard-coded https scheme: Cloud terminates TLS
  // upstream and then sends `X-Forwarded-Proto: http` on an https request, so
  // that header cannot be trusted.
  final host = request.headers['host'] ?? 'localhost';

  switch ('/${request.url.path}') {
    case '/og.png':
      return Response.ok(ogPng, headers: {
        'content-type': 'image/png',
        'cache-control': 'public, max-age=3600',
      });
    case '/':
      return Response.ok(page(host),
          headers: {'content-type': 'text/html; charset=utf-8'});
    default:
      return Response.notFound('not found\n',
          headers: {'content-type': 'text/plain; charset=utf-8'});
  }
}

Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '3000');
  // Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
  // network, so bind the dual-stack wildcard. InternetAddress.anyIPv6 is
  // dual-stack unless v6Only is asked for.
  await shelf_io.serve(handle, InternetAddress.anyIPv6, port);
  stdout.writeln('hello_cloud: hello from $language, serving on [::]:$port');
}
