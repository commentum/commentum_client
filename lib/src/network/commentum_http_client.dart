import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import '../commentum_config.dart';
import '../models/error.dart';

/// Internal HTTP executor handling request dispatch, headers, timeouts, and logging.
class CommentumHttpClient {
  final CommentumConfig config;
  final http.Client _httpClient;

  /// Provider for injecting the current active authorization token.
  String? Function()? getAuthToken;

  /// Callback triggered when a 401 Unauthorized response is encountered. Returns true if relogin succeeded.
  Future<bool> Function()? onTokenExpired;

  CommentumHttpClient({
    required this.config,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Performs an HTTP request against the Commentum API server with retry and auto-relogin capabilities.
  Future<dynamic> request(
    String endpoint, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? params,
    bool useAuth = true,
  }) async {
    final url = Uri.parse('${config.baseUrl}$endpoint').replace(
      queryParameters: params,
    );

    final maxAttempts = config.autoRetry ? (config.maxRetries + 1) : 1;
    bool attemptedAuthRefresh = false;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      if (useAuth && getAuthToken != null) {
        final token = getAuthToken!();
        if (token != null) {
          headers['Authorization'] = 'Bearer $token';
        }
      }

      if (config.enableLogging && !config.verboseLogging && attempt == 0) {
        print('[Commentum] $method $url');
      }

      if (config.verboseLogging) {
        _logRequest(method, url, headers, body);
      }

      final stopwatch = Stopwatch()..start();

      try {
        http.Response response;
        final encodedBody = body != null ? jsonEncode(body) : null;

        switch (method.toUpperCase()) {
          case 'POST':
            response = await _httpClient
                .post(url, headers: headers, body: encodedBody)
                .timeout(config.receiveTimeout);
            break;
          case 'PUT':
            response = await _httpClient
                .put(url, headers: headers, body: encodedBody)
                .timeout(config.receiveTimeout);
            break;
          case 'PATCH':
            response = await _httpClient
                .patch(url, headers: headers, body: encodedBody)
                .timeout(config.receiveTimeout);
            break;
          case 'DELETE':
            response = await _httpClient
                .delete(url, headers: headers, body: encodedBody)
                .timeout(config.receiveTimeout);
            break;
          default:
            response = await _httpClient
                .get(url, headers: headers)
                .timeout(config.receiveTimeout);
        }

        stopwatch.stop();

        if (config.verboseLogging) {
          _logResponse(response, stopwatch.elapsedMilliseconds);
        }

        if (response.statusCode == 401 && useAuth) {
          if (!attemptedAuthRefresh && onTokenExpired != null) {
            attemptedAuthRefresh = true;
            final refreshed = await onTokenExpired!();
            if (refreshed) {
              continue;
            }
          }
          throw const CommentumAuthException(
              'Session expired or unauthorized. Please login again.', 401);
        }

        final dynamic responseBody;
        try {
          responseBody = jsonDecode(response.body);
        } catch (e) {
          throw CommentumServerException(
              'Invalid JSON response received from server', response.statusCode);
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          final errorMsg = responseBody is Map
              ? (responseBody['error']?.toString() ?? 'Unknown Server Error')
              : 'Unknown Server Error';
          
          final ex = CommentumServerException(errorMsg, response.statusCode);
          if (response.statusCode >= 500 && attempt < maxAttempts - 1) {
            await Future.delayed(config.retryDelay * (attempt + 1));
            continue;
          }
          throw ex;
        }

        return responseBody;
      } on TimeoutException catch (e) {
        stopwatch.stop();
        if (config.verboseLogging) _logError(e, stopwatch.elapsedMilliseconds);
        if (attempt < maxAttempts - 1) {
          await Future.delayed(config.retryDelay * (attempt + 1));
          continue;
        }
        throw CommentumNetworkException(
            'Request timed out: ${e.message ?? 'Exceeded timeout'}');
      } on http.ClientException catch (e, stackTrace) {
        stopwatch.stop();
        if (config.verboseLogging) {
          _logError(e, stopwatch.elapsedMilliseconds, stackTrace);
        }
        if (attempt < maxAttempts - 1) {
          await Future.delayed(config.retryDelay * (attempt + 1));
          continue;
        }
        throw CommentumNetworkException(
            'Network communication failure: ${e.message}');
      } catch (e, stackTrace) {
        stopwatch.stop();
        if (config.verboseLogging && attempt == maxAttempts - 1) {
          _logError(e, stopwatch.elapsedMilliseconds, stackTrace);
        }
        if (e is CommentumException) rethrow;
        throw CommentumNetworkException('Unexpected networking error: $e');
      }
    }
  }

  void _logRequest(
      String method, Uri url, Map<String, String> headers, dynamic body) {
    final buffer = StringBuffer();
    buffer.writeln(
        '╔══════════════════════════════════════════════════════════════╗');
    buffer.writeln('║ ↗️ REQUEST');
    buffer.writeln(
        '╠══════════════════════════════════════════════════════════════');
    buffer.writeln('║ URL: $method $url');
    buffer.writeln('║ Headers:');
    headers.forEach((k, v) => buffer.writeln('║   $k: $v'));
    if (body != null) {
      buffer.writeln('║ Body:');
      _prettyPrintJson(body, buffer);
    }
    buffer.writeln(
        '╚══════════════════════════════════════════════════════════════╝');
    dev.log(buffer.toString(), name: 'Commentum');
  }

  void _logResponse(http.Response response, int latencyMs) {
    final buffer = StringBuffer();
    buffer.writeln(
        '╔══════════════════════════════════════════════════════════════╗');
    buffer.writeln('║ ↘️ RESPONSE [${response.statusCode}] (${latencyMs}ms)');
    buffer.writeln(
        '╠══════════════════════════════════════════════════════════════');
    buffer.writeln('║ Headers:');
    response.headers.forEach((k, v) => buffer.writeln('║   $k: $v'));
    buffer.writeln('║ Body:');
    try {
      final json = jsonDecode(response.body);
      _prettyPrintJson(json, buffer);
    } catch (_) {
      buffer.writeln('║   ${response.body}');
    }
    buffer.writeln(
        '╚══════════════════════════════════════════════════════════════╝');
    dev.log(buffer.toString(), name: 'Commentum');
  }

  void _logError(dynamic error, int latencyMs, [StackTrace? stackTrace]) {
    final buffer = StringBuffer();
    buffer.writeln(
        '╔══════════════════════════════════════════════════════════════╗');
    buffer.writeln('║ ❌ ERROR (${latencyMs}ms)');
    buffer.writeln(
        '╠══════════════════════════════════════════════════════════════');
    buffer.writeln('║ Error: $error');
    if (stackTrace != null) {
      buffer.writeln('║ StackTrace:');
      final traceLines = stackTrace.toString().split('\n').take(5);
      for (var line in traceLines) {
        if (line.isNotEmpty) buffer.writeln('║   $line');
      }
    }
    buffer.writeln(
        '╚══════════════════════════════════════════════════════════════╝');
    dev.log(buffer.toString(), name: 'Commentum', error: error);
  }

  void _prettyPrintJson(dynamic json, StringBuffer buffer) {
    var spaces = '║   ';
    var encoder = const JsonEncoder.withIndent('  ');
    var prettyString = encoder.convert(json);
    prettyString
        .split('\n')
        .forEach((element) => buffer.writeln('$spaces$element'));
  }

  void dispose() {
    _httpClient.close();
  }
}
