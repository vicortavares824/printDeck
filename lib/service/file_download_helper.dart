import 'dart:io';

import 'package:common/data/dto/files/remote_file_mixin.dart';
import 'package:common/service/moonraker/file_service.dart';
import 'package:common/util/logger.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileDownloadHelper {
  /// Initiates download of a RemoteFile from the active printer, displays a progress
  /// modal, saves the file to local device storage, and provides options to open/share.
  static Future<void> downloadFileWithProgress({
    required BuildContext context,
    required WidgetRef ref,
    required RemoteFile file,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DownloadProgressDialog(
        file: file,
        ref: ref,
      ),
    );
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  final RemoteFile file;
  final WidgetRef ref;

  const _DownloadProgressDialog({
    required this.file,
    required this.ref,
  });

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

enum _DownloadStatus {
  downloading,
  saving,
  success,
  error,
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0.0;
  String _statusMessage = 'Iniciando download...';
  _DownloadStatus _status = _DownloadStatus.downloading;
  String? _errorMessage;
  String? _savedFilePath;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      final fileService = widget.ref.read(fileServiceSelectedProvider);
      final downloadStream = fileService.downloadFile(
        filePath: widget.file.absolutPath,
        overWriteLocal: true,
      );

      File? tempDownloadedFile;

      await for (final event in downloadStream) {
        if (!mounted) return;
        if (event is FileDownloadProgress) {
          setState(() {
            _progress = event.progress;
            _statusMessage =
                'Baixando da impressora: ${(event.progress * 100).toInt()}%';
          });
        } else if (event is FileDownloadComplete) {
          tempDownloadedFile = event.file;
        }
      }

      if (tempDownloadedFile == null || !await tempDownloadedFile.exists()) {
        throw Exception('Arquivo temporário não encontrado após o download.');
      }

      if (!mounted) return;
      setState(() {
        _status = _DownloadStatus.saving;
        _statusMessage = 'Salvando arquivo no dispositivo...';
      });

      // Salvar em pasta permanente do dispositivo
      final destinationDir = await _getDestinationDirectory();
      await destinationDir.create(recursive: true);

      final finalPath = '${destinationDir.path}/${widget.file.name}';
      final finalFile = await tempDownloadedFile.copy(finalPath);

      logger.i('Arquivo da impressora salvo com sucesso em: ${finalFile.path}');

      if (mounted) {
        setState(() {
          _status = _DownloadStatus.success;
          _savedFilePath = finalFile.path;
          _statusMessage = 'Download concluído com sucesso!';
        });
      }
    } catch (e, stack) {
      logger.e('Erro ao baixar arquivo da impressora: $e', e, stack);
      if (mounted) {
        setState(() {
          _status = _DownloadStatus.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _statusMessage = 'Falha no download';
        });
      }
    }
  }

  Future<Directory> _getDestinationDirectory() async {
    // No Android, tentar salvar na pasta Download visível ao usuário
    if (Platform.isAndroid) {
      final androidDownload = Directory('/storage/emulated/0/Download');
      if (await androidDownload.exists()) {
        final printDeckFolder = Directory('${androidDownload.path}/PrintDeck');
        if (!await printDeckFolder.exists()) {
          try {
            await printDeckFolder.create(recursive: true);
            return printDeckFolder;
          } catch (_) {}
        } else {
          return printDeckFolder;
        }
        return androidDownload;
      }
    }

    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) return downloadsDir;
    } catch (_) {}

    return await getApplicationDocumentsDirectory();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            _status == _DownloadStatus.success
                ? Icons.check_circle
                : (_status == _DownloadStatus.error
                    ? Icons.error_outline
                    : Icons.cloud_download),
            color: _status == _DownloadStatus.success
                ? Colors.greenAccent
                : (_status == _DownloadStatus.error
                    ? Colors.redAccent
                    : theme.colorScheme.primary),
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _status == _DownloadStatus.success
                  ? 'Download Concluído'
                  : (_status == _DownloadStatus.error
                      ? 'Erro no Download'
                      : 'Baixando Arquivo'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.file.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          if (_status == _DownloadStatus.downloading ||
              _status == _DownloadStatus.saving) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _status == _DownloadStatus.saving ? null : _progress,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _statusMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ] else if (_status == _DownloadStatus.success) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Salvo no dispositivo em:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.greenAccent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    _savedFilePath ?? '',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ] else if (_status == _DownloadStatus.error) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Text(
                _errorMessage ?? 'Ocorreu um erro inesperado durante o download.',
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (_status == _DownloadStatus.downloading ||
            _status == _DownloadStatus.saving) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ] else if (_status == _DownloadStatus.success) ...[
          if (_savedFilePath != null)
            ElevatedButton.icon(
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Compartilhar / Abrir'),
              onPressed: () {
                Share.shareXFiles(
                  [XFile(_savedFilePath!)],
                  subject: 'Arquivo ${widget.file.name}',
                );
              },
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ] else if (_status == _DownloadStatus.error) ...[
          TextButton(
            onPressed: () {
              setState(() {
                _status = _DownloadStatus.downloading;
                _progress = 0.0;
                _errorMessage = null;
              });
              _startDownload();
            },
            child: const Text('Tentar novamente'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ],
    );
  }
}
