/// CarLyricsController 单测（真实 StreamController + 纯逻辑，不 mock 平台）
///
/// 覆盖：行切换去重、暂停恢复、切歌重置与异步歌词、范围关闭、refresh 重算。

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/player.dart';

/// 构造歌曲
Song song(String key, String title, String artist) => Song(
      id: key,
      sourceId: 'test',
      title: title,
      artist: artist,
      duration: 60,
    );

LyricLine line(int ms, String text) =>
    LyricLine(time: Duration(milliseconds: ms), text: text);

void main() {
  late StreamController<Duration> pos;
  late StreamController<Song?> songs;
  late StreamController<bool> playing;

  final lyrics = <String, Lyrics>{
    'a': Lyrics(
      songId: 'a',
      sourceId: 's',
      lines: <LyricLine>[
        line(0, '第一句'),
        line(2000, '第二句'),
        line(4000, '第三句'),
      ],
    ),
  };

  final pushed = <CarLyricsMetadata?>[];
  CarLyricsConfig config = const CarLyricsConfig(
    scope: CarLyricsScope.all,
    slot: CarLyricsSlot.title,
  );
  var bt = true;
  var car = false;

  setUp(() {
    pos = StreamController<Duration>.broadcast();
    songs = StreamController<Song?>.broadcast();
    playing = StreamController<bool>.broadcast();
    pushed.clear();
    config = const CarLyricsConfig(scope: CarLyricsScope.all, slot: CarLyricsSlot.title);
    bt = true;
    car = false;
  });

  tearDown(() async {
    await pos.close();
    await songs.close();
    await playing.close();
  });

  CarLyricsController build() => CarLyricsController(
        positionStream: pos.stream,
        songStream: songs.stream,
        playingStream: playing.stream,
        lyricsOf: (key) async => lyrics[key.split(':').last],
        onMetadata: pushed.add,
        config: () => config,
        bluetoothConnected: () => bt,
        carDetected: () => car,
      );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('播放中随位置推送歌词行，同一行不重复', () async {
    final c = build();
    songs.add(song('a', '夜行', '陈粒'));
    playing.add(true);
    await settle();
    pos.add(const Duration(milliseconds: 100));
    await settle();
    expect(pushed.last, const CarLyricsMetadata(title: '第一句', artist: '陈粒 - 夜行'));

    final count = pushed.length;
    pos.add(const Duration(milliseconds: 500));
    await settle();
    expect(pushed.length, count, reason: '同一行不应重复推送');

    pos.add(const Duration(milliseconds: 2500));
    await settle();
    expect(pushed.last, const CarLyricsMetadata(title: '第二句', artist: '陈粒 - 夜行'));
    await c.dispose();
  });

  test('暂停：清除覆盖恢复真实歌名', () async {
    final c = build();
    songs.add(song('a', '夜行', '陈粒'));
    playing.add(true);
    pos.add(const Duration(milliseconds: 100));
    await settle();
    playing.add(false);
    await settle();
    expect(pushed.last, isNull);
    await c.dispose();
  });

  test('切歌：立即恢复，随后用新歌词推送', () async {
    final c = build();
    lyrics['b'] = Lyrics(songId: 'b', sourceId: 's', lines: <LyricLine>[line(0, 'B 第一句')]);
    songs.add(song('a', '夜行', '陈粒'));
    playing.add(true);
    pos.add(const Duration(milliseconds: 100));
    await settle();
    songs.add(song('b', '另一首', '某人'));
    await settle();
    // 切歌会恢复真实元数据（随后新歌词可能立即补推）
    expect(pushed, contains(isNull));
    pos.add(const Duration(milliseconds: 100));
    await settle();
    expect(pushed.last, const CarLyricsMetadata(title: 'B 第一句', artist: '某人 - 另一首'));
    await c.dispose();
  });

  test('范围关闭（off）：不注入', () async {
    config = const CarLyricsConfig(scope: CarLyricsScope.off);
    final c = build();
    songs.add(song('a', '夜行', '陈粒'));
    playing.add(true);
    pos.add(const Duration(milliseconds: 100));
    await settle();
    expect(pushed.where((m) => m != null), isEmpty);
    await c.dispose();
  });

  test('未连蓝牙：不注入', () async {
    bt = false;
    final c = build();
    songs.add(song('a', '夜行', '陈粒'));
    playing.add(true);
    pos.add(const Duration(milliseconds: 100));
    await settle();
    expect(pushed.where((m) => m != null), isEmpty);
    await c.dispose();
  });

  test('refresh：配置从 off 改为 all 后补推', () async {
    config = const CarLyricsConfig(scope: CarLyricsScope.off);
    final c = build();
    songs.add(song('a', '夜行', '陈粒'));
    playing.add(true);
    pos.add(const Duration(milliseconds: 100));
    await settle();
    expect(pushed.where((m) => m != null), isEmpty);

    config = const CarLyricsConfig(scope: CarLyricsScope.all);
    c.refresh();
    await settle();
    expect(pushed.last, const CarLyricsMetadata(title: '第一句', artist: '陈粒 - 夜行'));
    await c.dispose();
  });
}
