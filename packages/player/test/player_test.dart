import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:player/player.dart';

void main() {
  test('PlayerImpl implements Player', () {
    final player = PlayerImpl();
    expect(player, isA<Player>());
    player.dispose();
  });

  test('initial state is idle', () {
    final player = PlayerImpl();
    expect(player.currentState, PlayerState.idle);
    expect(player.queue, isEmpty);
    expect(player.currentIndex, -1);
    player.dispose();
  });
}