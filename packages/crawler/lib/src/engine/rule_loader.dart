import 'dart:convert';
import 'dart:io';
import 'rule_config.dart';

/// 规则加载器：从 JSON 字符串或文件加载规则配置
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
  static RuleConfig? loadFromFile(String filePath) {
    try {
      final file = File(filePath);
      final content = file.readAsStringSync();
      return loadFromJson(content);
    } catch (e) {
      return null;
    }
  }

  /// 从目录加载所有规则配置
  static List<RuleConfig> loadAllFromDirectory(String dirPath) {
    final configs = <RuleConfig>[];
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return configs;

      for (final file in dir.listSync().whereType<File>()) {
        if (file.path.endsWith('.json')) {
          final config = loadFromFile(file.path);
          if (config != null) {
            configs.add(config);
          }
        }
      }
    } catch (_) {}
    return configs;
  }
}