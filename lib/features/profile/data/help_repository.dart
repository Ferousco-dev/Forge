import '../../../core/api/api_client.dart';
import '../../../core/mock/models.dart';

/// `21_help_support.md`.
class HelpRepository {
  HelpRepository({required ApiClient client}) : _client = client;
  final ApiClient _client;

  /// Public — no token required. Cached aggressively client-side.
  Future<List<HelpArticle>> fetchArticles({String? category}) async {
    final json = await _client.get(
      '/help/articles',
      authenticated: false,
      query: category == null ? null : <String, String>{'category': category},
    );
    return (json['items'] as List? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(HelpArticle.fromJson)
        .toList(growable: false);
  }

  Future<TicketResult> submitTicket({
    required String category,
    required String subject,
    required String message,
    String? relatedTransactionId,
    String? relatedJobId,
  }) async {
    final json = await _client.post(
      '/help/tickets',
      authenticated: true,
      body: <String, dynamic>{
        'category': category,
        'subject': subject,
        'message': message,
        if (relatedTransactionId != null)
          'related_transaction_id': relatedTransactionId,
        if (relatedJobId != null) 'related_job_id': relatedJobId,
      },
    );
    return TicketResult(
      ticketId: json['ticket_id'] as String,
      estimatedResponse: json['estimated_response'] as String? ?? '',
    );
  }
}

class TicketResult {
  const TicketResult({
    required this.ticketId,
    required this.estimatedResponse,
  });
  final String ticketId;
  final String estimatedResponse;
}
