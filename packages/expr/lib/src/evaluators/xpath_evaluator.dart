import 'package:xml/xml.dart';
import '../expression.dart';
import 'evaluator_interface.dart';

/// XPath 执行器（使用 xml 包实现基础 XPath 查询）
///
/// 支持的 XPath 语法子集：
/// - /root/child          → 绝对路径
/// - //element            → 任意深度查找
/// - element[@attr='val'] → 属性过滤
/// - /text()              → 获取文本
class XPathEvaluator implements ExpressionEvaluator {
  @override
  dynamic evaluate(ParseResult result, dynamic data) {
    if (data is! String) {
      throw ArgumentError('XPath evaluator requires XML/HTML string data');
    }

    final document = XmlDocument.parse(data);
    final results = _query(document, result.selector);

    if (results.isEmpty) return null;

    final values = results.where((s) => s.isNotEmpty).toList();
    return values.length == 1 ? values.first : values;
  }

  List<String> _query(XmlDocument document, String xpath) {
    final trimmed = xpath.trim();
    final isDeep = trimmed.startsWith('//');
    final parts = trimmed.split('/').where((p) => p.isNotEmpty).toList();

    if (parts.isEmpty) return [];

    final results = <String>[];
    _walkNodes(document, parts, 0, isDeep, results);
    return results;
  }

  void _walkNodes(XmlNode node, List<String> parts, int depth, bool isDeep, List<String> results) {
    if (depth >= parts.length) return;

    final part = parts[depth];
    final tagName = _extractTag(part);
    final attrFilter = _extractAttrFilter(part);

    for (final child in node.children) {
      if (child is! XmlElement) continue;

      final match = tagName == '*' || child.name.local == tagName;
      if (!match) {
        // 深度搜索时继续递归
        if (isDeep && depth == 0) {
          _walkNodes(child, parts, depth, isDeep, results);
        }
        continue;
      }

      // 检查属性过滤
      if (attrFilter != null) {
        final attr = child.getAttribute(attrFilter.$1);
        if (attr != attrFilter.$2) continue;
      }

      if (depth == parts.length - 1) {
        // 最后一个步骤，提取文本
        if (parts.last == 'text()') {
          results.add(child.innerText);
        } else {
          results.add(child.innerText.trim());
        }
      } else {
        // 继续下一层
        _walkNodes(child, parts, depth + 1, isDeep, results);
      }

      // 深度搜索：即使当前节点匹配，也继续搜索子节点
      if (isDeep && depth == 0) {
        _walkNodes(child, parts, depth, isDeep, results);
      }
    }
  }

  String _extractTag(String part) {
    final bracket = part.indexOf('[@');
    if (bracket >= 0) {
      return part.substring(0, bracket);
    }
    return part;
  }

  (String, String)? _extractAttrFilter(String part) {
    final match = RegExp(r"""\[@([a-zA-Z]+)\s*=\s*['"]([^'"]*)['"]\]""").firstMatch(part);
    if (match != null) {
      return (match.group(1)!, match.group(2)!);
    }
    return null;
  }
}