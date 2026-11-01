/// 歌词数据与装配 —— 对应原型 app.js 的 LYRIC_DATA 与 lyricEntries()。
///
/// 原型不内置受版权保护的歌词文本，这里是与曲目气质相符的**原创演示文本**
/// （逐字照搬原型），按曲目时长均分时间轴；未收录的曲目走空状态，不造假歌词。
/// 本地扫描曲目若在 core 侧解析出同名 .lrc，则优先使用真实时间轴。
library;

import 'package:core/core.dart';

/// 演示歌词（键 = 曲目 id，空串表示段落间隔，不参与高亮）
const Map<String, List<String>> kDemoLyrics = {
  'midnights#3': [
    '深夜三点我还醒着',
    '把心事翻来覆去地读',
    '我数着自己所有的错',
    '像数一场没完的雨',
    '他们说我不该这样想',
    '可我的影子比谁都长',
    '',
    '我也想做一个简单的人',
    '一杯温水，一晚安睡',
    '但镜子里的那个家伙',
    '还要陪我走完这一程',
    '',
    '如果我不再为难自己',
    '天会不会亮得更早一些',
    '我把答案留在明天',
    '先说声晚安给自己',
  ],
  'future-nostalgia#2': [
    '音乐已经开到最大',
    '脚尖先替我做了决定',
    '别在这时候说从前',
    '我今晚只想跟着鼓点走',
    '',
    '灯球转到哪一面',
    '我就把哪一面点亮',
    '你的名字留在门口',
    '想进来得先学会跳舞',
    '',
    '别停，别问我为什么',
    '拍子比道理更诚实',
    '明天的事交给明天',
    '现在只管把地板踩热',
    '',
    '这一夜还没有结束',
    '我还不想回到安静里',
  ],
  'ok-computer#2': [
    '请为我倒一杯安静',
    '城市在窗外咳了一整夜',
    '每个人都举着小屏幕',
    '照着自己不认识的脸',
    '',
    '我在人群里练习微笑',
    '像练习一门快忘掉的语言',
    '谁都可以被推荐给你',
    '谁也不必真的被记住',
    '',
    '如果机器的梦也有重量',
    '它大概压得人抬不起头',
    '我想找一个没有信号的地方',
    '把这一天慢慢删掉',
    '',
    '等我把话说得足够小声',
    '世界会不会也跟着安静',
  ],
  'back-to-black#5': [
    '我把窗帘拉得很紧',
    '让房间和我一起变暗',
    '你走的时候没关灯',
    '我就一直亮着等你回来',
    '',
    '咖啡凉成昨夜的形状',
    '杯底有一道浅浅的痕',
    '我学着不提起你的名字',
    '却在每个路口遇见它',
    '',
    '黑也好，黑得干净',
    '至少不用假装还很好',
    '等我把这首歌唱完',
    '就真的不再回头了',
    '',
    '有些告别要说两次',
    '一次给你，一次给自己',
  ],
  'rumours#3': [
    '长途车把风景甩在身后',
    '我把话说给风听',
    '从前那条路我认得',
    '但我不想再走一次',
    '',
    '你寄来的信我没有拆',
    '放在抽屉最深的角落',
    '有些答案拆开就输了',
    '有些沉默已经够了',
    '',
    '山那边还是山',
    '人走了，路才显得宽',
    '我这次要走得很慢',
    '把丢下的自己一件件捡回来',
    '',
    '等的不是谁回头',
    '是等我自己愿意往前走',
  ],
  'abbey-road#7': [
    '冬天拖得太久了',
    '我已经很久没有笑',
    '天边有一小块亮',
    '像是有人在敲门',
    '',
    '冰在屋檐下慢慢松开',
    '风里第一次有了土的味道',
    '我把外套搭在肩上',
    '想出去走走',
    '',
    '太阳来了',
    '这一次我要站在光里',
    '小小的、暖暖的，正好',
    '把整个冬天都换掉',
    '',
    '路过的人也在抬头',
    '好像大家都轻了一点',
  ],
  'blonde#7': [
    '夜里三点的海很安静',
    '车停在没有灯的坡上',
    '你的名字像一块糖',
    '含着含着就化了',
    '',
    '我总在失去之后才温柔',
    '总在走远之后才想起回头',
    '电话按到一半就挂断',
    '我怕听见你说你很好',
    '',
    '我们都长大了，也都走散了',
    '我把这当成一种成全',
    '天亮之前我要学着放手',
    '哪怕只是先练习一下',
    '',
    '方向盘还是朝着老地方',
    '我却没有再开过去',
  ],
  'dark-side-of-the-moon#4': [
    '闹钟响的时候我还年轻',
    '眨眼就该为明天发愁',
    '阳光从窗帘缝里滑过去',
    '一整天谁也没抓住',
    '',
    '有人在赶一趟很长的路',
    '有人把日子折成小小的方块',
    '我们都以为时间还有很多',
    '它却在背后轻轻关门',
    '',
    '别让这一年空着过',
    '别把想说的话留到下个春天',
    '钟摆不等人',
    '它只负责往前走',
    '',
    '今天的我比昨天旧一点',
    '但也比昨天更认得自己',
  ],
  'blue#8': [
    '我想给这条河写封信',
    '请它把冬天带走',
    '桌上的杯子还有一点温',
    '窗外的雪已经下了一天',
    '',
    '我会唱这首给很远的人',
    '唱给那些再也见不到的脸',
    '我会坐火车去看一场雪',
    '然后再一个人回来',
    '',
    '河水流过结冰的地方',
    '声音很轻，却一直在走',
    '等春天来的时候',
    '我想我会好一点',
    '',
    '有些名字不能说出口',
    '只能放进这样的夜里',
  ],
};

/// 歌词来源（原型 lyricSource 的三种取值）
enum LyricSource {
  /// 同名 .lrc 解析结果
  lrc,

  /// 内置演示文本
  demo,

  /// 没有歌词
  none,
}

/// 一行歌词（[at] 为 null 表示段落间隔）
class LyricEntry {
  /// 行文本（空串 = 段落间隔）
  final String text;

  /// 该行起始时间（null = 不参与高亮）
  final Duration? at;

  /// 构造歌词行
  const LyricEntry({required this.text, this.at});

  /// 是否为段落间隔
  bool get isGap => text.isEmpty;
}

/// 装配结果：来源 + 行列表
class LyricScript {
  /// 来源
  final LyricSource source;

  /// 行列表
  final List<LyricEntry> entries;

  /// 构造装配结果
  const LyricScript({required this.source, required this.entries});

  /// 是否有可展示的歌词
  bool get hasLyrics => source != LyricSource.none && entries.isNotEmpty;
}

/// 前奏留白秒数（原型 lead）
const double kLyricLead = 5;

/// 从 core 的 [Lyrics] 与演示文本装配歌词脚本。
///
/// 优先级与原型一致：.lrc → 演示文本 → 空。
/// 演示文本时间轴：span = max(24, duration - lead - 6)，逐非空行均分。
LyricScript buildLyricScript({
  required String trackId,
  required int durationSeconds,
  Lyrics? fromSource,
}) {
  final lines = fromSource?.lines ?? const <LyricLine>[];
  if (lines.isNotEmpty) {
    return LyricScript(
      source: LyricSource.lrc,
      entries: [
        for (final line in lines)
          LyricEntry(
            text: line.text,
            at: line.text.isEmpty ? null : line.time,
          ),
      ],
    );
  }

  final raw = kDemoLyrics[trackId];
  if (raw == null || raw.isEmpty) {
    return const LyricScript(source: LyricSource.none, entries: []);
  }

  final timed = raw.where((line) => line.isNotEmpty).length;
  final span = (durationSeconds - kLyricLead - 6) < 24
      ? 24.0
      : durationSeconds - kLyricLead - 6;
  final step = span / (timed == 0 ? 1 : timed);
  var k = 0;
  final entries = <LyricEntry>[];
  for (final line in raw) {
    if (line.isEmpty) {
      entries.add(const LyricEntry(text: '', at: null));
      continue;
    }
    entries.add(LyricEntry(
      text: line,
      at: Duration(milliseconds: ((kLyricLead + step * k) * 1000).round()),
    ));
    k++;
  }
  return LyricScript(source: LyricSource.demo, entries: entries);
}

/// 当前活动行下标（等价原型 updateLyrics 的线性扫描：取最后一个 at <= pos）
int activeLyricIndex(List<LyricEntry> entries, Duration position) {
  var active = -1;
  for (var i = 0; i < entries.length; i++) {
    final at = entries[i].at;
    if (at != null && position >= at) active = i;
  }
  return active;
}
