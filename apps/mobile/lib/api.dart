import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'generated/api_routes.dart';

const apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8787',
);

class ApiFailure implements Exception {
  ApiFailure(this.status, this.message, [this.current, this.code]);
  final int status;
  final String message;
  final dynamic current;
  final String? code;
  @override
  String toString() => message;
}

class Api {
  Api(this.token, {this.base = apiBase});
  final String token;
  final String base;
  Future<Map<String, dynamic>> request(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = Uri.parse('$base$path');
    final headers = {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final r =
        await (body == null
                ? http.get(uri, headers: headers)
                : http.post(uri, headers: headers, body: jsonEncode(body)))
            .timeout(const Duration(seconds: 30));
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 400) {
      throw ApiFailure(
        r.statusCode,
        data['error']?.toString() ?? 'Ошибка API',
        data['current'],
        data['code']?.toString(),
      );
    }
    return data;
  }

  Future<String> upload(String path) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$base${ApiRoutes.uploadPhoto}'),
    );
    req.headers['Authorization'] = 'Bearer $token';
    req.files.add(
      await http.MultipartFile.fromPath(
        'file',
        path,
        contentType: MediaType.parse(lookupMimeType(path) ?? 'image/jpeg'),
      ),
    );
    final r = await http.Response.fromStream(
      await req.send(),
    ).timeout(const Duration(seconds: 60));
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 400) {
      throw ApiFailure(
        r.statusCode,
        data['error']?.toString() ?? 'Ошибка загрузки фото',
        data['current'],
        data['code']?.toString(),
      );
    }
    return data['id'] as String;
  }
}
