/// OCR + LLM Pipeline Test Screen
///
/// Full B1 scenario: 4 documents -> OCR -> LLM -> Track B result
///
/// Run this by:
/// 1. Long-press "CivicLens" title on home screen
/// 2. Tap "Test OCR"

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/inference/ocr_service.dart';
import '../../core/inference/llama_client.dart';

class OcrTestScreen extends StatefulWidget {
  const OcrTestScreen({super.key});

  @override
  State<OcrTestScreen> createState() => _OcrTestScreenState();
}

enum _TestPhase { idle, ocr, loadingModel, inference, done }

class _OcrTestScreenState extends State<OcrTestScreen> {
  final OcrService _ocrService = OcrService();
  LlamaClient? _llamaClient;
  _TestPhase _phase = _TestPhase.idle;
  String _status = 'Tap "Run Full Pipeline" to start';
  final List<_OcrDocResult> _ocrResults = [];
  String _llmResponse = '';
  int _ocrTimeMs = 0;
  int _llmTimeMs = 0;
  int _totalTimeMs = 0;

  bool get _isRunning => _phase != _TestPhase.idle && _phase != _TestPhase.done;

  final List<_TestDoc> _testDocs = [
    _TestDoc('D12', 'Birth certificate'),
    _TestDoc('D05', 'Lease agreement'),
    _TestDoc('D06', 'Utility bill'),
    _TestDoc('D13', 'Immunization record'),
  ];

  Future<Uint8List> _loadAsset(String name) async {
    final byteData = await rootBundle.load('assets/test_docs/$name.jpg');
    return byteData.buffer.asUint8List();
  }

  Future<String?> _findModel() async {
    final docDir = await getApplicationDocumentsDirectory();
    final modelPath = '${docDir.path}/gemma-4-E2B-it-Q4_K_M.gguf';
    if (await File(modelPath).exists()) {
      final size = await File(modelPath).length();
      if (size > 2000000000) return modelPath;
    }
    return null;
  }

  String _buildTrackBPrompt(Map<int, String> ocrTexts, int docCount) {
    final buffer = StringBuffer();
    for (var i = 0; i < ocrTexts.length; i++) {
      final desc = i < _testDocs.length ? _testDocs[i].description : 'Document ${i + 1}';
      buffer.writeln('--- $desc ---');
      buffer.writeln(ocrTexts[i] ?? '');
      buffer.writeln();
    }
    final extractedText = buffer.toString();

    return '<start_of_turn>user\n'
        'You are helping a family prepare their Boston Public Schools registration packet.\n'
        '\n'
        'The BPS registration checklist requires:\n'
        '- Proof of child\'s age (birth certificate or passport)\n'
        '- TWO proofs of Boston residency from DIFFERENT categories\n'
        '- Current immunization record\n'
        '\n'
        'I have extracted text from $docCount documents using OCR:\n'
        '\n'
        '$extractedText\n'
        '\n'
        'Analyze what documents are present and whether they satisfy BPS requirements.\n'
        '\n'
        'Respond with a JSON object containing:\n'
        '- "requirements": array of objects each with "requirement", "status" (satisfied/questionable/missing), "matched_document", and "evidence"\n'
        '- "duplicate_category_flag": boolean\n'
        '- "family_summary": string summarizing readiness\n'
        '<end_of_turn>\n'
        '<start_of_turn>model\n';
  }

  Future<void> _runFullPipeline() async {
    final totalStopwatch = Stopwatch()..start();

    setState(() {
      _phase = _TestPhase.ocr;
      _status = 'Phase 1: Running OCR on 4 documents...';
      _ocrResults.clear();
      _llmResponse = '';
      _ocrTimeMs = 0;
      _llmTimeMs = 0;
    });

    // --- Phase 1: OCR ---
    final ocrReady = await _ocrService.initialize();
    if (!ocrReady) {
      setState(() {
        _status = 'ERROR: OCR failed to initialize';
        _phase = _TestPhase.done;
      });
      return;
    }

    final ocrStopwatch = Stopwatch()..start();
    final ocrTexts = <int, String>{};

    for (var i = 0; i < _testDocs.length; i++) {
      final doc = _testDocs[i];
      setState(() => _status = 'OCR: Processing ${doc.id} (${doc.description})...');

      try {
        final bytes = await _loadAsset(doc.id);
        final result = await _ocrService.extractText(bytes);

        ocrTexts[i] = result.text;
        setState(() {
          _ocrResults.add(_OcrDocResult(
            docId: doc.id,
            description: doc.description,
            success: result.hasText && result.text.length > 50,
            textLength: result.text.length,
            preview: result.text.isEmpty
                ? '(NO TEXT EXTRACTED)'
                : (result.text.length > 150
                    ? '${result.text.substring(0, 150)}...'
                    : result.text),
          ));
        });
      } catch (e) {
        ocrTexts[i] = '';
        setState(() {
          _ocrResults.add(_OcrDocResult(
            docId: doc.id,
            description: doc.description,
            success: false,
            error: e.toString(),
          ));
        });
      }
    }

    ocrStopwatch.stop();
    _ocrTimeMs = ocrStopwatch.elapsedMilliseconds;
    _ocrService.dispose();

    final ocrSuccessCount = _ocrResults.where((r) => r.success).length;
    if (ocrSuccessCount == 0) {
      setState(() {
        _status = 'ERROR: No text extracted from any document';
        _phase = _TestPhase.done;
      });
      return;
    }

    // --- Phase 2: Load LLM ---
    setState(() {
      _phase = _TestPhase.loadingModel;
      _status = 'Phase 2: Loading Gemma model...';
    });

    final modelPath = await _findModel();
    if (modelPath == null) {
      setState(() {
        _status = 'ERROR: Model not found. Run "Test Inference" first to verify model is installed.';
        _phase = _TestPhase.done;
      });
      return;
    }

    _llamaClient = LlamaClient();
    final modelLoaded = await _llamaClient!.initialize(
      modelPath: modelPath,
      onProgress: (progress) {
        setState(() {
          _status = 'Loading model: ${(progress * 100).toStringAsFixed(0)}%';
        });
      },
    );

    if (!modelLoaded) {
      setState(() {
        _status = 'ERROR: Failed to load model.\n${_llamaClient?.lastError ?? "Unknown error"}';
        _phase = _TestPhase.done;
      });
      return;
    }

    // --- Phase 3: LLM Inference ---
    setState(() {
      _phase = _TestPhase.inference;
      _status = 'Phase 3: Running LLM inference on OCR text...';
    });

    final prompt = _buildTrackBPrompt(ocrTexts, _testDocs.length);
    final llmStopwatch = Stopwatch()..start();

    final response = await _llamaClient!.chat(
      prompt: prompt,
      maxTokens: 2048,
      onProgress: (progress, {phase}) {
        setState(() {
          final pct = (progress * 100).toStringAsFixed(0);
          final sec = llmStopwatch.elapsed.inSeconds;
          final hint = phase == null || phase.isEmpty ? '' : '\n$phase';
          _status = 'LLM: $pct% (${sec}s)$hint';
        });
      },
    );

    llmStopwatch.stop();
    _llmTimeMs = llmStopwatch.elapsedMilliseconds;
    totalStopwatch.stop();
    _totalTimeMs = totalStopwatch.elapsedMilliseconds;

    _llamaClient?.dispose();
    _llamaClient = null;

    setState(() {
      _phase = _TestPhase.done;
      if (response.isSuccess) {
        _llmResponse = response.rawText ?? '(empty response)';
        _status = 'Pipeline complete!\n'
            'OCR: ${_ocrTimeMs}ms ($ocrSuccessCount/4 docs) | '
            'LLM: ${(_llmTimeMs / 1000).toStringAsFixed(1)}s | '
            'Total: ${(_totalTimeMs / 1000).toStringAsFixed(1)}s';
      } else {
        _llmResponse = '';
        _status = 'LLM inference failed: ${response.errorMessage}';
      }
    });
  }

  @override
  void dispose() {
    _llamaClient?.dispose();
    _ocrService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('B1 Pipeline Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _isRunning ? null : _runFullPipeline,
              child: Text(_isRunning ? 'Running...' : 'Run Full Pipeline'),
            ),
            const SizedBox(height: 12),
            if (_isRunning)
              const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_status, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  if (_ocrResults.isNotEmpty) ...[
                    Text('OCR Results', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ..._ocrResults.map((r) => Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(
                                r.success ? Icons.check_circle : Icons.error,
                                color: r.success ? Colors.green : Colors.red,
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Text('${r.docId}: ${r.description}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const Spacer(),
                              if (r.textLength != null)
                                Text('${r.textLength} chars', style: const TextStyle(fontSize: 12)),
                            ]),
                            if (r.preview != null) ...[
                              const SizedBox(height: 4),
                              Text(r.preview!, style: const TextStyle(fontSize: 11, color: Colors.black54),
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                            ],
                            if (r.error != null)
                              Text('Error: ${r.error}', style: const TextStyle(color: Colors.red, fontSize: 12)),
                          ],
                        ),
                      ),
                    )),
                  ],
                  if (_llmResponse.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('LLM Response (${(_llmTimeMs / 1000).toStringAsFixed(1)}s)',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: SelectableText(
                        _llmResponse,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestDoc {
  final String id;
  final String description;

  _TestDoc(this.id, this.description);
}

class _OcrDocResult {
  final String docId;
  final String description;
  final bool success;
  final int? textLength;
  final String? preview;
  final String? error;

  _OcrDocResult({
    required this.docId,
    required this.description,
    required this.success,
    this.textLength,
    this.preview,
    this.error,
  });
}
