/// results.json → report.md（只写脚本能证明的事实）
library;

import 'dart:convert';

const String _bt = '\u0060';
String _code(Object? s) => _bt + (s ?? '').toString() + _bt;
String get _fence => _bt * 3;

const Map<String, String> _icon = {
  'PASS': '✅',
  'WARN': '⚠️',
  'FAIL': '❌',
  'TIMEOUT': '⏱️',
  'SKIP': '⏭️',
  'EMPTY_STATE': '⬜',
  'ERROR': '💥',
};

String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;

String _rel(String path) {
  final norm = path.replaceAll(r'\', '/');
  final idx = norm.indexOf('build/');
  return idx >= 0 ? norm.substring(idx) : norm;
}

/// 渲染单次跑批的报告
String renderReport(Map<String, dynamic> payload) {
  final results = (payload['results'] as List).cast<Map<String, dynamic>>();
  final summary = (payload['summary'] as Map).cast<String, dynamic>();
  final out = <String>[];

  out.add('# 发版前集成检查报告（脚本事实）');
  out.add('');
  out.add('| 项 | 值 |');
  out.add('| --- | --- |');
  out.add('| 用例计划 | ' + (payload['plan'] ?? '') + ' |');
  out.add('| 尺寸 | ' + (payload['size'] ?? '-') + ' |');
  out.add('| App 驱动地址 | ' + (payload['appUri'] ?? '-') + ' |');
  out.add('| 开始 | ' + (payload['startedAt'] ?? '') + ' |');
  out.add('| 用例数 | ' + results.length.toString() + ' |');
  out.add('| 结论 | ' +
      summary.entries.map((e) => e.key + ' ' + e.value.toString()).join(' / ') +
      ' |');
  out.add('');

  out.add('## 1. 逐条结论');
  out.add('');
  out.add('| # | 用例 | 结论 | 耗时(ms) | 失败步骤 | 截图 |');
  out.add('| --- | --- | --- | --- | --- | --- |');
  for (var i = 0; i < results.length; i++) {
    final r = results[i];
    final shots = (r['shots'] as List)
        .map((s) => '[' + _baseName(s.toString()) + '](' + _rel(s.toString()) + ')')
        .join(' ');
    String fail = '—';
    if (r['failStep'] != null) {
      final fs = r['failStep'] as Map;
      fail = _code(fs['type']) +
          ' ' +
          (fs['error'] ?? '').toString().split('\n').first.replaceAll('|', '/');
    }
    out.add('| ' +
        (i + 1).toString() +
        ' | ' +
        r['id'] +
        ' ' +
        r['title'] +
        ' | ' +
        (_icon[r['status']] ?? '') +
        ' ' +
        r['status'] +
        ' | ' +
        r['ms'].toString() +
        ' | ' +
        fail +
        ' | ' +
        (shots.isEmpty ? '—' : shots) +
        ' |');
  }
  out.add('');

  final failed = results.where((r) =>
      r['status'] == 'FAIL' || r['status'] == 'TIMEOUT' || r['status'] == 'ERROR');
  out.add('## 2. 失败明细（原文，未加工）');
  out.add('');
  if (failed.isEmpty) {
    out.add('无。');
  } else {
    for (final r in failed) {
      out.add('### ' + r['id'] + ' ' + r['title'] + ' — ' + r['status']);
      out.add('');
      final fs = r['failStep'] as Map?;
      if (fs != null) {
        out.add('失败步骤：第 ' + ((fs['i'] as int) + 1).toString() + ' 步 ' + _code(fs['type']));
        out.add('');
        out.add(_fence);
        out.add((fs['error'] ?? '').toString());
        out.add(_fence);
        out.add('');
      }
    }
  }

  final noisy = results.where((r) => (r['errors'] as List).isNotEmpty);
  out.add('## 3. 运行时异常 / soft 失败');
  out.add('');
  if (noisy.isEmpty) {
    out.add('无。');
  } else {
    for (final r in noisy) {
      out.add('- **' + r['id'] + '**');
      for (final e in r['errors'] as List) {
        out.add('  - ' + _code(e));
      }
    }
  }
  out.add('');

  out.add('## 4. 截图清单');
  out.add('');
  for (final r in results) {
    for (final s in r['shots'] as List) {
      out.add('- ' + r['id'] + ' → [' + _baseName(s.toString()) + '](' + _rel(s.toString()) + ')');
    }
  }
  out.add('');
  out.add('> 本文件只陈述事实；异常归因与放行建议见同目录 analysis.md。');
  return out.join('\n');
}

/// 多尺寸汇总报告（页面 × 尺寸 矩阵）
String renderIndex(String root, List<Map<String, dynamic>> groups) {
  final out = <String>[];
  final caseIds = [for (final r in groups.first['results'] as List) (r as Map)['id'] as String];
  out.add('# 三断点 × 全页面 布局巡检报告');
  out.add('');
  out.add('| 项 | 值 |');
  out.add('| --- | --- |');
  out.add('| 目录 | ' + root + ' |');
  out.add('| 尺寸 | ' + groups.map((g) => g['size'].toString()).join(' / ') + ' |');
  out.add('| 页面数 | ' + caseIds.length.toString() + ' |');
  out.add('');
  out.add('## 1. 状态矩阵');
  out.add('');
  out.add('| 页面 | ' + groups.map((g) => g['size'].toString()).join(' | ') + ' |');
  out.add('| --- | ' + groups.map((_) => '---').join(' | ') + ' |');
  for (final id in caseIds) {
    final rows = groups.map((g) {
      final hit = (g['results'] as List).cast<Map>().where((r) => r['id'] == id);
      if (hit.isEmpty) return '—';
      final r = hit.first;
      return (_icon[r['status']] ?? '') + ' ' + r['status'].toString();
    }).join(' | ');
    final title = (groups.first['results'] as List)
        .cast<Map>()
        .firstWhere((r) => r['id'] == id)['title'];
    out.add('| ' + id + ' ' + title.toString() + ' | ' + rows + ' |');
  }
  out.add('| **通过率** | ' +
      groups.map((g) {
        final rs = (g['results'] as List).cast<Map>();
        final ok = rs.where((r) => r['status'] == 'PASS').length;
        return ok.toString() + '/' + rs.length.toString();
      }).join(' | ') +
      ' |');
  out.add('');
  out.add('## 2. 各尺寸汇总');
  out.add('');
  for (final g in groups) {
    final s = (g['summary'] as Map).cast<String, dynamic>();
    out.add('- **' +
        g['size'].toString() +
        '**：' +
        s.entries.map((e) => e.key + ' ' + e.value.toString()).join(' / '));
  }
  out.add('');
  out.add('## 3. 问题明细');
  out.add('');
  var any = false;
  for (final g in groups) {
    for (final r in (g['results'] as List).cast<Map>()) {
      final errs = (r['errors'] as List);
      if (r['status'] == 'PASS' && errs.isEmpty) continue;
      any = true;
      out.add('### [' + g['size'].toString() + '] ' + r['id'].toString() + ' ' + r['title'].toString() + ' — ' + r['status'].toString());
      out.add('');
      final fs = r['failStep'] as Map?;
      if (fs != null) {
        out.add(_fence);
        out.add((fs['error'] ?? '').toString());
        out.add(_fence);
      }
      for (final e in errs) {
        out.add('- ' + _code(e));
      }
      out.add('');
    }
  }
  if (!any) out.add('无。所有页面在三档下都渲染成功，且没有捕获到布局溢出或运行时异常。');
  return out.join('\n');
}

/// 写 results.json 文本
String encodeResults(Map<String, dynamic> payload) =>
    const JsonEncoder.withIndent('  ').convert(payload);
