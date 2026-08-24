import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'domain.dart';
import 'storage_security.dart';

const String builtInSearchProviderId = 'duckduckgo-html';
const String braveSearchProviderId = 'brave-api';
const String _searchUserAgent =
    'Kristin-Local-Agent WebSearch/1.0 (+https://github.com/alex00Pirotskyi/kris.ai)';
const int _maxSearchQueryCharacters = 2000;
const int _maxSearchTitleCharacters = 512;
const int _maxSearchSnippetCharacters = 4096;
const int _maxSearchUrlCharacters = 2048;
const int _maxBuiltInResponseBytes = 1024 * 1024;

class SearchProviderRequest {
  const SearchProviderRequest({
    required this.query,
    this.count = 10,
    this.cancellation,
    this.isCancelled,
  });

  final String query;
  final int count;
  final Future<void>? cancellation;
  final bool Function()? isCancelled;
}

class SearchProviderResult {
  const SearchProviderResult({
    required this.title,
    required this.url,
    required this.snippet,
  });

  final String title;
  final String url;
  final String snippet;

  Map<String, String> toMap() => <String, String>{
        'title': title,
        'url': url,
        'snippet': snippet,
      };
}

class SearchProviderResponse {
  const SearchProviderResponse({
    required this.providerId,
    required this.results,
    required this.fallbackUsed,
    required this.providerFailures,
  });

  final String providerId;
  final List<SearchProviderResult> results;
  final bool fallbackUsed;
  final List<String> providerFailures;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'providerId': providerId,
        'resultCount': results.length,
        'fallbackUsed': fallbackUsed,
        if (providerFailures.isNotEmpty) 'providerFailures': providerFailures,
      };
}

class SearchProviderProbe {
  const SearchProviderProbe({
    required this.available,
    required this.message,
    this.providerId = '',
    this.resultCount = 0,
    this.providerFailures = const <String>[],
  });

  final bool available;
  final String message;
  final String providerId;
  final int resultCount;
  final List<String> providerFailures;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'available': available,
        if (providerId.isNotEmpty) 'providerId': providerId,
        'resultCount': resultCount,
        if (providerFailures.isNotEmpty) 'providerFailures': providerFailures,
      };
}

abstract interface class SearchProvider {
  String get id;

  Future<List<SearchProviderResult>> search(SearchProviderRequest request);
}

class SearchProviderRouter {
  const SearchProviderRouter({
    required this.builtIn,
    this.preferred,
  });

  final SearchProvider builtIn;
  final SearchProvider? preferred;

  Future<SearchProviderResponse> search(SearchProviderRequest request) async {
    _validateRequest(request);
    final providers = <SearchProvider>[
      if (preferred != null) preferred!,
      builtIn,
    ];
    final failures = <String>[];
    for (var index = 0; index < providers.length; index++) {
      final provider = providers[index];
      try {
        final results = await provider.search(request);
        return SearchProviderResponse(
          providerId: provider.id,
          results: List<SearchProviderResult>.unmodifiable(results),
          fallbackUsed: index > 0,
          providerFailures: List<String>.unmodifiable(failures),
        );
      } on ProductException catch (error) {
        if (error.code == 'cancelled') {
          rethrow;
        }
        failures.add('${provider.id}:${error.code}');
      } on TimeoutException {
        failures.add('${provider.id}:search_provider_timeout');
      } on SocketException {
        failures.add('${provider.id}:search_provider_network_error');
      } on Object {
        failures.add('${provider.id}:search_provider_error');
      }
    }
    throw ProductException(
      'web_search_unavailable',
      'Web search is currently unavailable.',
      details: <String, dynamic>{'providerFailures': failures},
    );
  }

  Future<SearchProviderProbe> probe() async {
    try {
      final response = await search(
        const SearchProviderRequest(
          query: 'Kristin web search readiness',
          count: 1,
        ),
      );
      return SearchProviderProbe(
        available: true,
        providerId: response.providerId,
        resultCount: response.results.length,
        providerFailures: response.providerFailures,
        message: response.providerId == builtInSearchProviderId
            ? 'Built-in web search is available.'
            : 'Web search is available.',
      );
    } on ProductException catch (error) {
      return SearchProviderProbe(
        available: false,
        message: 'Web search is currently unavailable.',
        providerFailures: _failureStrings(error.details['providerFailures']),
      );
    } on Object {
      return const SearchProviderProbe(
        available: false,
        message: 'Web search is currently unavailable.',
      );
    }
  }

  static void _validateRequest(SearchProviderRequest request) {
    final query = request.query.trim();
    if (query.isEmpty) {
      throw ProductException(
        'argument_required',
        'A web-search query is required.',
      );
    }
    if (query.length > _maxSearchQueryCharacters) {
      throw ProductException(
        'query_too_long',
        'Web-search query exceeds the bounded length limit.',
      );
    }
    if (request.count < 1 || request.count > 20) {
      throw ProductException(
        'argument_value_invalid',
        'Web-search result count must be between 1 and 20.',
      );
    }
    _throwIfCancelled(request);
  }
}

class BuiltInDuckDuckGoSearchProvider implements SearchProvider {
  BuiltInDuckDuckGoSearchProvider({
    required this.timeout,
    required int maxBytes,
    SearchHttpTransport? transport,
  })  : maxBytes = min(maxBytes, _maxBuiltInResponseBytes),
        transport = transport ?? defaultSearchHttpTransport;

  @override
  String get id => builtInSearchProviderId;

  final Duration timeout;
  final int maxBytes;
  final SearchHttpTransport transport;

  @override
  Future<List<SearchProviderResult>> search(
    SearchProviderRequest request,
  ) async {
    SearchProviderRouter._validateRequest(request);
    final query = request.query.trim();
    final response = await transport(
      SearchHttpRequest(
        method: 'POST',
        uri: Uri.https('html.duckduckgo.com', '/html/'),
        headers: const <String, String>{
          HttpHeaders.acceptHeader:
              'text/html,application/xhtml+xml;q=0.9,*/*;q=0.1',
          HttpHeaders.acceptLanguageHeader: 'en-US,en;q=0.8',
          HttpHeaders.contentTypeHeader:
              'application/x-www-form-urlencoded; charset=utf-8',
          HttpHeaders.userAgentHeader: _searchUserAgent,
        },
        body: utf8.encode('q=${Uri.encodeQueryComponent(query)}'),
        timeout: timeout,
        maxBytes: maxBytes,
        cancellation: request.cancellation,
        isCancelled: request.isCancelled,
      ),
    );
    _throwIfCancelled(request);
    if (response.body.length > maxBytes) {
      throw ProductException(
        'search_provider_response_too_large',
        'The built-in web-search response exceeded its bounded size limit.',
      );
    }
    if (const <int>{202, 403, 429}.contains(response.statusCode)) {
      throw ProductException(
        'search_provider_rate_limited',
        'The built-in web-search provider is temporarily rate limited.',
        details: <String, dynamic>{
          'providerId': id,
          if (response.headers['retry-after']?.isNotEmpty == true)
            'retryAfter': response.headers['retry-after'],
        },
      );
    }
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw ProductException(
        'search_provider_redirect_rejected',
        'The built-in web-search endpoint returned an unexpected redirect.',
      );
    }
    if (response.statusCode != 200) {
      throw ProductException(
        'search_provider_http_error',
        'The built-in web-search endpoint returned an unexpected status.',
        details: <String, dynamic>{'status': response.statusCode},
      );
    }
    final contentType = response.headers[HttpHeaders.contentTypeHeader]
            ?.toLowerCase()
            .trim() ??
        '';
    if (contentType.isNotEmpty && !contentType.startsWith('text/html')) {
      throw ProductException(
        'search_provider_mime_rejected',
        'The built-in web-search endpoint returned an unexpected content type.',
      );
    }
    late String html;
    try {
      html = utf8.decode(response.body);
    } on FormatException {
      throw ProductException(
        'search_provider_malformed_response',
        'The built-in web-search response is not valid UTF-8 HTML.',
      );
    }
    final lower = html.toLowerCase();
    if (lower.contains('bots use duckduckgo too') ||
        lower.contains('anomaly-modal') ||
        lower.contains('challenge-form')) {
      throw ProductException(
        'search_provider_rate_limited',
        'The built-in web-search provider requested a challenge.',
      );
    }
    final results = parseDuckDuckGoHtmlResults(html, limit: request.count);
    if (results.isEmpty) {
      throw ProductException(
        'search_provider_malformed_response',
        'The built-in web-search response did not contain usable results.',
      );
    }
    return results;
  }
}

typedef BraveSearchCallback = Future<List<Map<String, String>>> Function({
  required String query,
  required String apiKey,
  required int count,
});

class BraveSearchProvider implements SearchProvider {
  const BraveSearchProvider({
    required this.apiKey,
    required this.callback,
  });

  final String apiKey;
  final BraveSearchCallback callback;

  @override
  String get id => braveSearchProviderId;

  @override
  Future<List<SearchProviderResult>> search(
    SearchProviderRequest request,
  ) async {
    SearchProviderRouter._validateRequest(request);
    if (apiKey.trim().isEmpty) {
      throw ProductException(
        'search_provider_not_configured',
        'The optional Brave Search provider is not configured.',
      );
    }
    final operation = callback(
      query: request.query.trim(),
      apiKey: apiKey,
      count: request.count,
    );
    final raw = await _awaitCancellationAware(operation, request);
    _throwIfCancelled(request);
    return normalizeSearchResults(raw, limit: request.count);
  }
}

class SearchHttpRequest {
  const SearchHttpRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
    required this.timeout,
    required this.maxBytes,
    this.cancellation,
    this.isCancelled,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int> body;
  final Duration timeout;
  final int maxBytes;
  final Future<void>? cancellation;
  final bool Function()? isCancelled;
}

class SearchHttpResponse {
  const SearchHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;
}

typedef SearchHttpTransport = Future<SearchHttpResponse> Function(
  SearchHttpRequest request,
);

Future<SearchHttpResponse> defaultSearchHttpTransport(
  SearchHttpRequest request,
) async {
  if (request.uri.scheme != 'https' ||
      request.uri.host.toLowerCase() != 'html.duckduckgo.com' ||
      request.uri.path != '/html/' ||
      request.uri.hasQuery) {
    throw ProductException(
      'search_provider_endpoint_rejected',
      'The built-in web-search transport only permits its fixed HTTPS endpoint.',
    );
  }
  if (request.method != 'POST') {
    throw ProductException(
      'search_provider_method_rejected',
      'The built-in web-search transport only permits POST.',
    );
  }
  if (request.maxBytes < 1 || request.maxBytes > _maxBuiltInResponseBytes) {
    throw ProductException(
      'search_provider_limit_invalid',
      'The built-in web-search response limit is invalid.',
    );
  }
  _throwIfCancelledRaw(request.isCancelled);
  final client = HttpClient()
    ..connectionTimeout = request.timeout <= const Duration(seconds: 5)
        ? request.timeout
        : const Duration(seconds: 5);
  StreamSubscription<void>? cancellationSubscription;
  if (request.cancellation != null) {
    cancellationSubscription = request.cancellation!.asStream().listen((_) {
      client.close(force: true);
    });
  }
  try {
    final outgoing = await _awaitCancellationAwareRaw(
      client.openUrl(request.method, request.uri).timeout(request.timeout),
      request.cancellation,
      request.isCancelled,
    );
    outgoing.followRedirects = false;
    outgoing.maxRedirects = 0;
    for (final entry in request.headers.entries) {
      outgoing.headers.set(entry.key, entry.value);
    }
    if (request.body.isNotEmpty) {
      outgoing.add(request.body);
    }
    final incoming = await _awaitCancellationAwareRaw(
      outgoing.close().timeout(request.timeout),
      request.cancellation,
      request.isCancelled,
    );
    final headers = <String, String>{};
    incoming.headers.forEach((name, values) {
      if (values.isNotEmpty) {
        headers[name.toLowerCase()] = values.join(', ');
      }
    });
    if (incoming.statusCode != 200) {
      return SearchHttpResponse(
        statusCode: incoming.statusCode,
        headers: Map<String, String>.unmodifiable(headers),
        body: const <int>[],
      );
    }
    final body = await _readBoundedSearchBody(
      incoming,
      maxBytes: request.maxBytes,
      timeout: request.timeout,
      cancellation: request.cancellation,
      isCancelled: request.isCancelled,
    );
    return SearchHttpResponse(
      statusCode: incoming.statusCode,
      headers: Map<String, String>.unmodifiable(headers),
      body: List<int>.unmodifiable(body),
    );
  } on ProductException {
    rethrow;
  } on TimeoutException {
    _throwIfCancelledRaw(request.isCancelled);
    throw ProductException(
      'search_provider_timeout',
      'The built-in web-search request timed out.',
    );
  } on SocketException {
    _throwIfCancelledRaw(request.isCancelled);
    throw ProductException(
      'search_provider_network_error',
      'The built-in web-search endpoint could not be reached.',
    );
  } on HttpException {
    _throwIfCancelledRaw(request.isCancelled);
    throw ProductException(
      'search_provider_network_error',
      'The built-in web-search request failed.',
    );
  } finally {
    await cancellationSubscription?.cancel();
    client.close(force: true);
  }
}

Future<List<int>> _readBoundedSearchBody(
  HttpClientResponse response, {
  required int maxBytes,
  required Duration timeout,
  Future<void>? cancellation,
  bool Function()? isCancelled,
}) async {
  final bytes = <int>[];
  final iterator = StreamIterator<List<int>>(response);
  try {
    while (await _awaitCancellationAwareRaw(
      iterator.moveNext().timeout(timeout),
      cancellation,
      isCancelled,
    )) {
      final chunk = iterator.current;
      if (bytes.length + chunk.length > maxBytes) {
        throw ProductException(
          'search_provider_response_too_large',
          'The built-in web-search response exceeded its bounded size limit.',
        );
      }
      bytes.addAll(chunk);
    }
  } finally {
    await iterator.cancel();
  }
  return List<int>.unmodifiable(bytes);
}

List<SearchProviderResult> parseDuckDuckGoHtmlResults(
  String html, {
  int limit = 10,
}) {
  final boundedLimit = limit.clamp(1, 20).toInt();
  final links = <({String href, String title})>[];
  final snippets = <String>[];
  final anchorPattern = RegExp(
    r'<a\b([^>]*)>([\s\S]*?)</a>',
    caseSensitive: false,
  );
  for (final match in anchorPattern.allMatches(html)) {
    final attributes = match.group(1) ?? '';
    final classes = (_attribute(attributes, 'class') ?? '')
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty)
        .map((value) => value.toLowerCase())
        .toSet();
    if (classes.contains('result__a')) {
      final href = _attribute(attributes, 'href') ?? '';
      final title = _plainHtmlText(match.group(2) ?? '');
      if (href.isNotEmpty && title.isNotEmpty) {
        links.add((href: href, title: title));
      }
    } else if (classes.contains('result__snippet')) {
      snippets.add(_plainHtmlText(match.group(2) ?? ''));
    }
  }
  final results = <SearchProviderResult>[];
  final seen = <String>{};
  for (var index = 0;
      index < links.length && results.length < boundedLimit;
      index++) {
    final url = normalizePublicSearchResultUrl(links[index].href);
    if (url == null || !seen.add(url)) {
      continue;
    }
    final title = _boundedText(links[index].title, _maxSearchTitleCharacters);
    if (title.isEmpty) {
      continue;
    }
    final snippet = index < snippets.length
        ? _boundedText(snippets[index], _maxSearchSnippetCharacters)
        : '';
    results.add(
      SearchProviderResult(
        title: title,
        url: url,
        snippet: snippet,
      ),
    );
  }
  return List<SearchProviderResult>.unmodifiable(results);
}

List<SearchProviderResult> normalizeSearchResults(
  Iterable<Map<String, String>> raw, {
  int limit = 10,
}) {
  final boundedLimit = limit.clamp(1, 20).toInt();
  final results = <SearchProviderResult>[];
  final seen = <String>{};
  for (final item in raw) {
    if (results.length >= boundedLimit) {
      break;
    }
    final url = normalizePublicSearchResultUrl(item['url'] ?? '');
    if (url == null || !seen.add(url)) {
      continue;
    }
    final title = _boundedText(item['title'] ?? '', _maxSearchTitleCharacters);
    if (title.isEmpty) {
      continue;
    }
    results.add(
      SearchProviderResult(
        title: title,
        url: url,
        snippet: _boundedText(
          item['snippet'] ?? item['description'] ?? '',
          _maxSearchSnippetCharacters,
        ),
      ),
    );
  }
  return List<SearchProviderResult>.unmodifiable(results);
}

String? normalizePublicSearchResultUrl(String input) {
  var raw = _decodeHtmlEntities(input).trim();
  if (raw.isEmpty || raw.length > 8192) {
    return null;
  }
  if (raw.startsWith('//')) {
    raw = 'https:$raw';
  }
  if (raw.startsWith('/')) {
    raw = Uri.https('duckduckgo.com', '/').resolve(raw).toString();
  }
  var uri = Uri.tryParse(raw);
  if (uri == null) {
    return null;
  }
  if (_isDuckDuckGoHost(uri.host) && uri.path.startsWith('/l/')) {
    final target = uri.queryParameters['uddg']?.trim() ?? '';
    if (target.isEmpty) {
      return null;
    }
    uri = Uri.tryParse(target);
    if (uri == null) {
      return null;
    }
  }
  if (uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      !_isPublicSearchHost(uri.host)) {
    return null;
  }
  final normalized = uri.replace(fragment: '').toString();
  if (normalized.length > _maxSearchUrlCharacters) {
    return null;
  }
  return normalized;
}

bool _isDuckDuckGoHost(String host) {
  final lower = host.toLowerCase();
  return lower == 'duckduckgo.com' || lower.endsWith('.duckduckgo.com');
}

bool _isPublicSearchHost(String host) {
  final lower = host.toLowerCase().replaceAll(RegExp(r'\.+$'), '');
  if (lower.isEmpty ||
      lower == 'localhost' ||
      lower.endsWith('.localhost') ||
      lower.endsWith('.local') ||
      lower.endsWith('.internal') ||
      lower.endsWith('.lan') ||
      lower.endsWith('.home.arpa')) {
    return false;
  }
  final address = InternetAddress.tryParse(lower);
  if (address == null) {
    return true;
  }
  if (address.isLoopback) {
    return false;
  }
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
    return _isPublicIpv4(bytes);
  }
  if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
    if (bytes.every((value) => value == 0)) {
      return false;
    }
    if ((bytes[0] & 0xfe) == 0xfc ||
        (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) ||
        bytes[0] == 0xff) {
      return false;
    }
    final mappedIpv4 = bytes.take(10).every((value) => value == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    if (mappedIpv4) {
      return _isPublicIpv4(bytes.sublist(12));
    }
  }
  return true;
}

bool _isPublicIpv4(List<int> bytes) {
  final first = bytes[0];
  final second = bytes[1];
  if (first == 0 || first == 10 || first == 127 || first >= 224) {
    return false;
  }
  if (first == 100 && second >= 64 && second <= 127) {
    return false;
  }
  if (first == 169 && second == 254) {
    return false;
  }
  if (first == 172 && second >= 16 && second <= 31) {
    return false;
  }
  if (first == 192 && second == 168) {
    return false;
  }
  if (first == 198 && (second == 18 || second == 19)) {
    return false;
  }
  return true;
}

String? _attribute(String attributes, String name) {
  final escaped = RegExp.escape(name);
  final doubleQuoted = RegExp(
    '$escaped\\s*=\\s*"([^"]*)"',
    caseSensitive: false,
  ).firstMatch(attributes);
  if (doubleQuoted != null) {
    return doubleQuoted.group(1);
  }
  final singleQuoted = RegExp(
    "$escaped\\s*=\\s*'([^']*)'",
    caseSensitive: false,
  ).firstMatch(attributes);
  return singleQuoted?.group(1);
}

String _plainHtmlText(String value) {
  final withoutTags = value.replaceAll(RegExp(r'<[^>]*>'), ' ');
  return _decodeHtmlEntities(withoutTags)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _decodeHtmlEntities(String value) {
  if (!value.contains('&')) {
    return value;
  }
  return value.replaceAllMapped(
    RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|quot|apos|lt|gt|nbsp);'),
    (match) {
      final token = match.group(1) ?? '';
      switch (token) {
        case 'amp':
          return '&';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'nbsp':
          return ' ';
      }
      int? codePoint;
      if (token.startsWith('#x')) {
        codePoint = int.tryParse(token.substring(2), radix: 16);
      } else if (token.startsWith('#')) {
        codePoint = int.tryParse(token.substring(1));
      }
      if (codePoint == null ||
          codePoint < 0 ||
          codePoint > 0x10ffff ||
          (codePoint >= 0xd800 && codePoint <= 0xdfff)) {
        return match.group(0) ?? '';
      }
      return String.fromCharCode(codePoint);
    },
  );
}

String _boundedText(String value, int maxCharacters) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= maxCharacters) {
    return normalized;
  }
  return normalized.substring(0, maxCharacters);
}

void _throwIfCancelled(SearchProviderRequest request) {
  _throwIfCancelledRaw(request.isCancelled);
}

void _throwIfCancelledRaw(bool Function()? isCancelled) {
  if (isCancelled?.call() == true) {
    throw ProductException('cancelled', 'Execution was cancelled.');
  }
}

Future<T> _awaitCancellationAware<T>(
  Future<T> operation,
  SearchProviderRequest request,
) =>
    _awaitCancellationAwareRaw(
      operation,
      request.cancellation,
      request.isCancelled,
    );

Future<T> _awaitCancellationAwareRaw<T>(
  Future<T> operation,
  Future<void>? cancellation,
  bool Function()? isCancelled,
) async {
  _throwIfCancelledRaw(isCancelled);
  if (cancellation == null) {
    return operation;
  }
  return Future.any<T>(<Future<T>>[
    operation,
    cancellation.then<T>((_) {
      throw ProductException('cancelled', 'Execution was cancelled.');
    }),
  ]);
}

List<String> _failureStrings(Object? value) {
  if (value is! Iterable) {
    return const <String>[];
  }
  return value
      .map((item) => item.toString())
      .where((item) => item.isNotEmpty)
      .take(8)
      .toList(growable: false);
}
