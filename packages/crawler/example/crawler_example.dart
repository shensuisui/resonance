import 'package:crawler/crawler.dart';

void main() {
  final url = HttpClient.resolveUrl('/search?keyword={keyword}&page={page}', {
    'keyword': '周杰伦',
    'page': '1',
  });
  print('Resolved URL: $url');
}