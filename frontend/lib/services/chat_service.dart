import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_service.dart';

class ChatService {
  final AuthService _authService;

  ChatService({AuthService? authService})
      : _authService = authService ?? AuthService();

  /// Send a message. Returns answer, confidence, and suggested follow-up questions.
  Future<ChatResponse> sendMessage(String message) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.chatbotEndpoint}/chat',
    );
    final resp = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode({'message': message}),
        )
        .timeout(ApiConfig.requestTimeout);

    if (resp.statusCode != 200) {
      final body = resp.body;
      String detail = 'Chat request failed';
      try {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        detail = decoded['detail']?.toString() ?? body;
      } catch (_) {
        if (body.isNotEmpty) detail = body;
      }
      throw ChatException(detail, resp.statusCode);
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final suggestionsList = data['suggestions'];
    final suggestions = suggestionsList is List
        ? (suggestionsList as List).map((e) => e.toString()).toList()
        : <String>[];

    return ChatResponse(
      response: data['response'] as String? ?? '',
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0.0,
      status: data['status'] as String? ?? 'success',
      suggestions: suggestions,
    );
  }

  /// Fetch suggested questions to show the user (max 4).
  Future<List<String>> getSuggestions({int limit = 4}) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.chatbotEndpoint}/suggestions',
    ).replace(queryParameters: {'limit': limit.toString()});
    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    if (resp.statusCode != 200) return ChatService.defaultSuggestions;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = data['suggestions'];
    if (list is! List || list.isEmpty) return ChatService.defaultSuggestions;
    return (list as List).map((e) => e.toString()).toList();
  }

  /// Default suggestion questions when API is unavailable.
  static const List<String> defaultSuggestions = [
    'How many devices do I have?',
    'What is my current energy usage?',
    'Explain the dashboard',
    'What is Volt Guard?',
  ];

  /// Add a custom Q&A entry to the chatbot dataset.
  Future<void> addDatasetEntry(String question, String answer) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.chatbotEndpoint}/dataset',
    );
    final resp = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode({'question': question.trim(), 'answer': answer.trim()}),
        )
        .timeout(ApiConfig.requestTimeout);
    if (resp.statusCode != 200) {
      String detail = resp.body;
      try {
        final d = jsonDecode(resp.body) as Map<String, dynamic>;
        detail = d['detail']?.toString() ?? resp.body;
      } catch (_) {}
      throw ChatException(detail, resp.statusCode);
    }
  }

  /// List custom Q&A entries.
  Future<List<DatasetEntry>> getCustomDataset() async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.chatbotEndpoint}/dataset',
    );
    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    if (resp.statusCode != 200) return [];
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final entries = data['entries'] as List? ?? [];
    return entries.map((e) {
      final m = e as Map<String, dynamic>;
      return DatasetEntry(
        id: m['id'] as String? ?? '',
        question: m['question'] as String? ?? '',
        answer: m['answer'] as String? ?? '',
      );
    }).toList();
  }

  /// Delete a custom Q&A entry by id.
  Future<void> deleteDatasetEntry(String entryId) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.chatbotEndpoint}/dataset/${Uri.encodeComponent(entryId)}',
    );
    final resp = await http.delete(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    if (resp.statusCode != 200) {
      String detail = resp.body;
      try {
        final d = jsonDecode(resp.body) as Map<String, dynamic>;
        detail = d['detail']?.toString() ?? resp.body;
      } catch (_) {}
      throw ChatException(detail, resp.statusCode);
    }
  }

  Future<Map<String, dynamic>> checkHealth() async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.chatbotEndpoint}/health',
    );
    final resp = await http.get(uri).timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) {
      return {'status': 'error', 'message': 'Health check failed'};
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}

class ChatResponse {
  final String response;
  final double confidence;
  final String status;
  final List<String> suggestions;

  ChatResponse({
    required this.response,
    required this.confidence,
    required this.status,
    this.suggestions = const [],
  });
}

class DatasetEntry {
  final String id;
  final String question;
  final String answer;

  DatasetEntry({required this.id, required this.question, required this.answer});
}

class ChatException implements Exception {
  final String message;
  final int statusCode;

  ChatException(this.message, this.statusCode);

  @override
  String toString() => 'ChatException: $message ($statusCode)';
}
