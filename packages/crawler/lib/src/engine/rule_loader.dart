/// 规则加载器：从 JSON 字符串或文件加载规则配置
///
/// 文件操作通过 [file_service] 条件导入实现，
/// Web 平台上文件方法返回空/null。

import 'dart:convert';
import '../file_service.dart';
import 'rule_config.dart';

class RuleLoader {
  /// 从 JSON 字符串加载规则配置
  static RuleConfig? loadFromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return RuleConfig.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  /// 从文件加载规则配置
  static Future<RuleConfig?> loadFromFile(String filePath) async {
    try {
      final content = await readFileAsString(filePath);
      return loadFromJson(content);
    } catch (e) {
      return null;
    }
  }

  /// 从目录加载所有 .json 规则配置
  static Future<List<RuleConfig>> loadAllFromDirectory(String dirPath) async {
    final configs = <RuleConfig>[];
    try {
      final files = await listFiles(dirPath, extension: '.json');
      for (final file in files) {
        final config = await loadFromFile(file);
        if (config != null) {
          configs.add(config);
        }
      }
    } catch (_) {}
    return configs;
  }
}
