import 'package:core/core.dart';

void main() {
  final song = Song(id: '1', sourceId: 'demo', title: 'Demo Song', artist: 'Demo Artist');
  print('Song: ${song.globalKey} - ${song.title}');
}