/// Simple inference test screen
///
/// Tests that llama.cpp loads the model and responds to prompts.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../core/inference/llama_client.dart';

class InferenceTestScreen extends StatefulWidget {
  const InferenceTestScreen({super.key});

  @override
  State<InferenceTestScreen> createState() => _InferenceTestScreenState();
}

class _InferenceTestScreenState extends State<InferenceTestScreen> {
  String _status = 'Not started';
  String _response = '';
  bool _isLoading = false;
  LlamaClient? _client;

  // Your Mac's WiFi IP address
  static const String _macIp = '192.168.86.21';
  static const String _modelUrl = 'http://$_macIp:8080/gemma-4-E2B-it-Q4_K_M.gguf';

  static const int _expectedModelSize = 3106731392; // 2.9 GB

  Future<String?> _findModel() async {
    final docDir = await getApplicationDocumentsDirectory();
    final modelPath = '${docDir.path}/gemma-4-E2B-it-Q4_K_M.gguf';

    setState(() {
      _status = 'Looking for model at:\n$modelPath';
    });

    if (await File(modelPath).exists()) {
      final size = await File(modelPath).length();
      if (size < _expectedModelSize * 0.95) {
        // Incomplete download -- delete and return null to trigger re-download
        setState(() {
          _status = 'Found incomplete model (${(size / 1024 / 1024).toStringAsFixed(0)} MB / '
              '${(_expectedModelSize / 1024 / 1024).toStringAsFixed(0)} MB). Deleting...';
        });
        await File(modelPath).delete();
        return null;
      }
      return modelPath;
    }

    return null;
  }

  Future<void> _downloadModel() async {
    setState(() {
      _status = 'Downloading model from $_modelUrl...\nThis will take several minutes (2.9GB)';
    });

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final modelPath = '${docDir.path}/gemma-4-E2B-it-Q4_K_M.gguf';
      final file = File(modelPath);

      final request = http.Request('GET', Uri.parse(_modelUrl));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        setState(() {
          _status = 'Download failed: HTTP ${response.statusCode}';
          _isLoading = false;
        });
        return;
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        if (totalBytes > 0) {
          final progress = receivedBytes / totalBytes;
          setState(() {
            _status = 'Downloading: ${(progress * 100).toStringAsFixed(1)}%\n'
                '${(receivedBytes / 1024 / 1024).toStringAsFixed(0)} MB / ${(totalBytes / 1024 / 1024).toStringAsFixed(0)} MB';
          });
        }
      }

      await sink.close();

      setState(() {
        _status = 'Download complete! Model saved to:\n$modelPath';
      });

    } catch (e) {
      setState(() {
        _status = 'Download error: $e\n\nMake sure your Mac and iPhone are on the same WiFi network.';
        _isLoading = false;
      });
    }
  }

  Future<void> _testInference() async {
    setState(() {
      _isLoading = true;
      _status = 'Looking for model...';
    });

    try {
      String? modelPath = await _findModel();

      if (modelPath == null) {
        // Model not found, offer to download
        setState(() {
          _status = 'Model not found locally.';
          _isLoading = false;
        });

        final shouldDownload = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Download Model?'),
            content: Text('Model not found. Download from Mac at $_modelUrl?\n\nThis will transfer 2.9GB over WiFi.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Download'),
              ),
            ],
          ),
        );

        if (shouldDownload == true) {
          setState(() => _isLoading = true);
          await _downloadModel();

          // Try to find model again after download
          modelPath = await _findModel();
          if (modelPath == null) {
            setState(() {
              _status = 'Model download failed or incomplete';
              _isLoading = false;
            });
            return;
          }
        } else {
          return;
        }
      }

      final file = File(modelPath);
      final size = await file.length();
      setState(() {
        _status = 'Model found!\nSize: ${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB\nLoading...';
      });

      // Initialize client
      _client = LlamaClient();
      final success = await _client!.initialize(
        modelPath: modelPath,
        onProgress: (progress) {
          setState(() {
            _status = 'Loading model: ${(progress * 100).toStringAsFixed(0)}%';
          });
        },
      );

      if (!success) {
        setState(() {
          _status = 'Failed to initialize model.\n\n${_client?.lastError ?? "Unknown error"}';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _status = 'Model loaded! Running inference...';
      });

      // Run simple inference test
      final response = await _client!.chat(
        prompt: 'What is 2+2? Answer with just the number.',
        maxTokens: 10,
      );

      setState(() {
        _status = 'Inference complete!';
        _response = response.rawText ?? 'No response';
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _client?.dispose();
    _client = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inference Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _isLoading ? null : _testInference,
              child: const Text('Test Inference'),
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              'Status:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(_status),
            const SizedBox(height: 20),
            if (_response.isNotEmpty) ...[
              Text(
                'Response:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_response),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
