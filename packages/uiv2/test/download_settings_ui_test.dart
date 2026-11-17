/// 下载设置 Notifier：默认值、持久化、新容器恢复
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/providers/providers.dart';

Future<void> _pumpMicrotasks() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late InMemoryDatabaseProvider db;
  late ProviderContainer c;

  setUp(() {
    db = InMemoryDatabaseProvider();
    c = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(c.dispose);
  });

  test('默认：artist_title / 256 / 85', () {
    expect(c.read(downloadNameOrderProvider), 'artist_title');
    expect(c.read(downloadCoverSizeProvider), 256);
    expect(c.read(downloadCoverQualityProvider), 85);
  });

  test('set 持久化到 settings，新容器可恢复', () async {
    await c.read(downloadNameOrderProvider.notifier).set('title_artist');
    await c.read(downloadCoverSizeProvider.notifier).set(512);
    await c.read(downloadCoverQualityProvider.notifier).set(90);

    expect(await db.settingsDao.get(DownloadSettingsKeys.nameOrder), 'title_artist');
    expect(await db.settingsDao.get(DownloadSettingsKeys.coverSize), '512');
    expect(await db.settingsDao.get(DownloadSettingsKeys.coverQuality), '90');

    final c2 = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(c2.dispose);
    c2.read(downloadNameOrderProvider);
    c2.read(downloadCoverSizeProvider);
    c2.read(downloadCoverQualityProvider);
    await _pumpMicrotasks();
    expect(c2.read(downloadNameOrderProvider), 'title_artist');
    expect(c2.read(downloadCoverSizeProvider), 512);
    expect(c2.read(downloadCoverQualityProvider), 90);
  });
}
