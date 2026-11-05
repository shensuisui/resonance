import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:resonance_demo_source/demo_server.dart';
import 'package:test/test.dart';

late DemoServer server;
late Uri origin;
late HttpClient client;

Future<HttpClientResponse> get(String path, {String method = 'GET'}) async {
  final request = await client.openUrl(method, origin.resolve(path));
  return request.close();
}

Future<String> bodyText(HttpClientResponse response) async =>
    utf8.decode(await response.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk)));

Future<Uint8List> bodyBytes(HttpClientResponse response) async {
  final bytes = await response.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
  return Uint8List.fromList(bytes);
}

void main() {
  setUpAll(() async {
    server = await DemoServer.load(Directory.current);
    origin = await server.start(host: '127.0.0.1', port: 0);
    client = HttpClient();
  });

  tearDownAll(() async {
    client.close(force: true);
    await server.close();
  });

  test('健康检查与规则源都可用，baseUrl 随 Host 生成', () async {
    final health = await get('/health');
    expect(health.statusCode, 200);
    expect(jsonDecode(await bodyText(health)), {'status': 'ok'});

    final response = await get('/rule.json');
    expect(response.statusCode, 200);
    final rule = jsonDecode(await bodyText(response)) as Map<String, dynamic>;
    expect(rule['source']['id'], 'demo_catalog');
    expect(rule['source']['baseUrl'], origin.toString().replaceAll(RegExp(r'/$'), ''));
    expect(rule['search'], isNotNull);
    expect(rule['songDetail'], isNotNull);
    expect(rule['lyric'], isNotNull);
  });

  test('搜索、空关键词和分页', () async {
    final hit = jsonDecode(await bodyText(await get('/search?keyword=blue&page=1')))
        as Map<String, dynamic>;
    expect(hit['songs'], isNotEmpty);

    final empty = jsonDecode(await bodyText(await get('/search?keyword=&page=1')))
        as Map<String, dynamic>;
    expect(empty['songs'], isEmpty);
  });

  test('曲目详情返回绝对封面与真实播放地址', () async {
    final response = await get('/songs/${Uri.encodeComponent('midnights-3')}');
    expect(response.statusCode, 200);
    final song = jsonDecode(await bodyText(response)) as Map<String, dynamic>;
    expect(song['id'], 'midnights-3');
    expect(song['title'], 'Anti-Hero');
    expect(song['coverUrl'], '${origin}/covers/midnights.jpg');
    expect(song['playUrl'], '${origin}/audio/demo.wav');
    expect(song['duration'], 253);
  });

  test('歌词是可直接解析的 LRC', () async {
    final response = await get('/lyrics/midnights-3');
    expect(response.statusCode, 200);
    expect(response.headers.contentType?.mimeType, 'text/plain');
    final text = await bodyText(response);
    expect(text, contains('[00:05.00]深夜三点我还醒着'));
    expect(text, contains('先说声晚安给自己'));
  });

  test('歌单列表与详情真实可用', () async {
    final list = jsonDecode(await bodyText(await get('/playlists'))) as Map<String, dynamic>;
    expect(list['playlists'], hasLength(7));

    final detail = jsonDecode(await bodyText(await get('/playlists/pl-night-drive')))
        as Map<String, dynamic>;
    expect(detail['name'], '深夜公路');
    expect(detail['songs'], hasLength(8));
    expect(detail['coverUrl'], isNotEmpty);
  });

  test('延迟参数真实阻塞，非法值返回 400', () async {
    final watch = Stopwatch()..start();
    final response = await get('/search?keyword=blue&d=0.12');
    await response.drain<void>();
    watch.stop();
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(100));

    final bad = await get('/search?keyword=blue&d=abc');
    expect(bad.statusCode, 400);
    expect(await bodyText(bad), contains('d'));
  });

  test('封面支持 Range 206', () async {
    final request = await client.getUrl(origin.resolve('/covers/midnights.jpg'));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-9');
    final response = await request.close();
    expect(response.statusCode, 206);
    expect(response.headers.contentType?.mimeType, 'image/jpeg');
    expect(response.headers.value(HttpHeaders.contentRangeHeader), startsWith('bytes 0-9/')); 
    final bytes = await bodyBytes(response);
    expect(bytes, hasLength(10));
    expect(bytes.take(2), [0xFF, 0xD8]);
  });

  test('WAV 支持 HEAD 与 Range，内容头正确', () async {
    final head = await get('/audio/demo.wav', method: 'HEAD');
    expect(head.statusCode, 200);
    expect(head.headers.contentType?.mimeType, 'audio/wav');
    expect(head.headers.contentLength, greaterThan(44));
    expect(head.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');

    final request = await client.getUrl(origin.resolve('/audio/demo.wav'));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=100-199');
    final partial = await request.close();
    expect(partial.statusCode, 206);
    expect(await bodyBytes(partial), hasLength(100));
  });

  test('不存在资源返回 404，目录穿越被拒绝', () async {
    expect((await get('/missing')).statusCode, 404);
    expect((await get('/covers/%2e%2e%2fdata%2fcatalog.json')).statusCode, 404);
  });
}
