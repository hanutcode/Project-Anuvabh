import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => message;
}

class HomeRepository {
  HomeRepository({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl =
          baseUrl ??
          const String.fromEnvironment('API_BASE_URL', defaultValue: '');
  final http.Client _client;
  final String _baseUrl;

  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    final base = _baseUrl.isNotEmpty
        ? _baseUrl
        : (kIsWeb ? Uri.base.origin : 'http://127.0.0.1:8080');
    final uri = Uri.parse('$base/api/$path');
    final request = http.Request(method, uri);
    request.headers['Content-Type'] = 'application/json';
    if (data != null) request.body = jsonEncode(data);
    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        throw ApiException(
          response.statusCode,
          body['error'] ?? 'Request failed.',
        );
      }
      return body;
    } on FormatException {
      throw Exception(
        'The data service is unavailable. Start the local app server and retry.',
      );
    } on http.ClientException {
      throw Exception(
        'Cannot connect to the app server. Check your connection and retry.',
      );
    }
  }

  void dispose() => _client.close();
}
