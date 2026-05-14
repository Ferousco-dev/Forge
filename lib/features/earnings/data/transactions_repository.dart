import '../../../core/api/api_client.dart';
import '../../../core/mock/models.dart';

/// `09_transactions.md` + `10_transaction_detail.md`.
class TransactionsRepository {
  TransactionsRepository({required ApiClient client}) : _client = client;
  final ApiClient _client;

  Future<TransactionsPage> fetchPage({
    Iterable<TransactionKind>? kinds,
    String? cursor,
    int limit = 30,
  }) async {
    final json = await _client.get(
      '/transactions',
      authenticated: true,
      query: <String, String>{
        'limit': limit.toString(),
        if (kinds != null && kinds.isNotEmpty)
          'kinds': kinds.map((k) => k.wire).join(','),
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    final items = (json['items'] as List? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(Transaction.fromJson)
        .toList(growable: false);
    return TransactionsPage(
      items: items,
      nextCursor: json['next_cursor'] as String?,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }

  Future<Transaction> fetchById(String id) async {
    final json = await _client.get(
      '/transactions/$id',
      authenticated: true,
    );
    return Transaction.fromJson(json);
  }
}

class TransactionsPage {
  const TransactionsPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });
  final List<Transaction> items;
  final String? nextCursor;
  final bool hasMore;
}
