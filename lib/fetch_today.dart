import 'dart:convert';

import 'package:http/http.dart' as http;

import 'today.dart';

final Uri todayUrl = Uri.parse(
  'https://larryhsiao.github.io/erelas/today.json',
);
const Duration fetchTimeout = Duration(seconds: 20);

Future<Today> fetchToday(http.Client client, Uri url) async {
  final reply = await client.get(url).timeout(fetchTimeout);
  if (reply.statusCode != 200) {
    throw http.ClientException('HTTP ${reply.statusCode}', url);
  }
  final json = jsonDecode(utf8.decode(reply.bodyBytes));
  return Today.fromJson(json as Map<String, dynamic>);
}
