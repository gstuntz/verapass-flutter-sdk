import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../errors.dart';
import '../result.dart';

/// A session as the client endpoints return it: no scores, nothing internal.
class ClientSession {
  const ClientSession({
    required this.id,
    required this.status,
    required this.challenge,
    required this.referenceReady,
    this.failureCode,
    this.failureFrame,
  });

  factory ClientSession.fromJson(Map<String, Object?> json) => ClientSession(
    id: json['id']! as String,
    status: FaceSessionStatus.parse(json['status']! as String),
    challenge: (json['challenge'] as List<Object?>?)?.cast<String>() ?? const [],
    referenceReady: json['reference_ready'] as bool? ?? false,
    failureCode: FaceFailureCode.parse(json['failure_code'] as String?),
    failureFrame: json['failure_frame'] as int?,
  );

  final String id;
  final FaceSessionStatus status;
  final List<String> challenge;
  final bool referenceReady;
  final FaceFailureCode? failureCode;
  final int? failureFrame;

  FaceVerificationResult toResult() => FaceVerificationResult(
    sessionId: id,
    status: status,
    failureCode: status == FaceSessionStatus.verificationPassed ? null : (failureCode ?? (status == FaceSessionStatus.expired ? FaceFailureCode.expired : null)),
    failureFrame: failureFrame,
  );
}

const clientTokenPrefix = 'fpct_';

/// Talks only to the client-token endpoints. Never sees or sends an API key.
class ClientApi {
  ClientApi(Uri apiUrl, this._token, {http.Client? client, this.timeout = const Duration(seconds: 60)})
    : _base = apiUrl.replace(path: '${apiUrl.path.replaceAll(RegExp(r'/+$'), '')}/api/v1/client/session'),
      _client = client ?? http.Client() {
    if (!_token.startsWith(clientTokenPrefix)) {
      throw const FaceVerificationException(FaceVerificationErrorCode.configurationError, 'clientToken must be a session client token (fpct_...)');
    }
  }

  final Uri _base;
  final String _token;
  final http.Client _client;
  final Duration timeout;

  Future<ClientSession> getSession() => _send(http.Request('GET', _base));

  /// Submits photos in order: facing the camera, then one per challenge action
  /// (field "frames"), or a single "probe" for sessions without a challenge.
  Future<ClientSession> verify(List<Uint8List> photos, {required bool liveness}) {
    final request = http.MultipartRequest('POST', _base.replace(path: '${_base.path}/verify'));
    final field = liveness ? 'frames' : 'probe';
    for (final (i, photo) in photos.indexed) {
      request.files.add(http.MultipartFile.fromBytes(field, photo, filename: '$field-$i.jpg'));
    }
    return _send(request);
  }

  Future<ClientSession> _send(http.BaseRequest request) async {
    request.headers['X-Client-Token'] = _token;
    http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request).timeout(timeout));
    } on TimeoutException catch (e) {
      throw FaceVerificationException(FaceVerificationErrorCode.networkError, 'The API did not answer in time', e);
    } on SocketException catch (e) {
      throw FaceVerificationException(FaceVerificationErrorCode.networkError, 'Could not reach the API', e);
    } on http.ClientException catch (e) {
      throw FaceVerificationException(FaceVerificationErrorCode.networkError, 'Could not reach the API', e);
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return ClientSession.fromJson(jsonDecode(response.body) as Map<String, Object?>);
    }
    var detail = '';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['detail'] is String) detail = body['detail'] as String;
    } on FormatException {
      // not JSON
    }
    throw httpError(response.statusCode, detail);
  }

  void close() => _client.close();
}

FaceVerificationException httpError(int status, String detail) {
  final message = detail.isEmpty ? 'HTTP $status' : detail;
  return switch (status) {
    401 => FaceVerificationException(FaceVerificationErrorCode.invalidToken, message),
    409 => FaceVerificationException(FaceVerificationErrorCode.sessionUsed, message),
    410 => FaceVerificationException(FaceVerificationErrorCode.sessionExpired, message),
    422 when detail.toLowerCase().contains('reference') => FaceVerificationException(FaceVerificationErrorCode.referenceMissing, message),
    >= 500 => FaceVerificationException(FaceVerificationErrorCode.serviceUnavailable, message),
    _ => FaceVerificationException(FaceVerificationErrorCode.requestRejected, message),
  };
}
