import 'dart:io';

import 'storage_security.dart';

class ProductErrorNormalizer {
  const ProductErrorNormalizer._();

  static ProductException normalize(Object error, {String? executable}) {
    if (error is ProductException) return error;
    if (error is ProcessException) {
      final message = error.message.toLowerCase();
      final target = executable?.trim().isNotEmpty == true
          ? executable!.trim()
          : error.executable;
      if (message.contains('cannot find the file') ||
          message.contains('no such file') ||
          message.contains('not found')) {
        return ProductException(
          'tool_executable_not_found',
          '$target is required for this step but Kristin cannot start it from the current process environment.',
          details: <String, dynamic>{
            'executable': target,
            'osError': error.message,
          },
        );
      }
      if (message.contains('permission') || message.contains('access denied')) {
        return ProductException(
          'tool_spawn_permission_denied',
          'Kristin found $target but the operating system refused to start it.',
          details: <String, dynamic>{
            'executable': target,
            'osError': error.message,
          },
        );
      }
      return ProductException(
        'tool_spawn_failed',
        'Kristin could not start $target.',
        details: <String, dynamic>{
          'executable': target,
          'osError': error.message,
        },
      );
    }
    if (error is FileSystemException) {
      return ProductException(
        'filesystem_operation_failed',
        error.message,
        details: <String, dynamic>{'path': error.path ?? ''},
      );
    }
    return ProductException(
      'operation_failed',
      error.toString(),
    );
  }

  static String userMessage(Object error) {
    final normalized = normalize(error);
    return '${normalized.code}: ${normalized.message}';
  }
}
