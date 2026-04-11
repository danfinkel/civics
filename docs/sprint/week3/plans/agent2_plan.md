# Agent 2 — Week 3 Plan: Eval Server + Monte Carlo Harness

**Week:** April 14–18, 2026  
**Owns:** `mobile/lib/eval/`, `research/eval/`, `mobile/scripts/`  
**Goal:** Build infrastructure for systematic performance measurement on device. By Friday: Mac can drive 50+ automated inference runs on iPhone without human intervention.

---

## Monday: Eval Server Foundation

### Morning (3 hours)
**Add dependencies to `pubspec.yaml`**

```yaml
dependencies:
  shelf: ^1.4.1
  shelf_router: ^1.1.4
```

Run `flutter pub get`.

**Create `mobile/lib/eval/eval_server.dart`**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

class EvalServer {
  final InferenceService _inferenceService;
  HttpServer? _server;
  int _inferenceCount = 0;
  int _lastInferenceMs = 0;
  
  EvalServer(this._inferenceService);
  
  Future<void> start({int port = 8080}) async {
    final router = Router();
    
    // Health check
    router.get('/health', (Request req) {
      return Response.ok(jsonEncode({
        'status': 'ok',
        'model': 'gemma4-e2b',
        'timestamp': DateTime.now().toIso8601String(),
      }), headers: {'content-type': 'application/json'});
    });
    
    // Single inference request
    router.post('/infer', (Request req) async {
      final body = jsonDecode(await req.readAsString());
      
      final imageB64 = body['image'] as String;
      final prompt = body['prompt'] as String;
      final track = body['track'] as String;
      final temperature = (body['temperature'] as num?)?.toDouble() ?? 0.0;
      final tokenBudget = (body['token_budget'] as num?)?.toInt();
      
      final imageBytes = base64Decode(imageB64);
      
      final stopwatch = Stopwatch()..start();
      
      String? rawResponse;
      try {
        rawResponse = await _inferenceService.inferRaw(
          imageBytes: imageBytes,
          prompt: prompt,
          temperature: temperature,
          tokenBudget: tokenBudget,
        );
        _inferenceCount++;
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'content-type': 'application/json'},
        );
      }
      
      stopwatch.stop();
      _lastInferenceMs = stopwatch.elapsedMilliseconds;
      
      return Response.ok(
        jsonEncode({
          'response': rawResponse,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'parse_ok': rawResponse != null && rawResponse.isNotEmpty,
        }),
        headers: {'content-type': 'application/json'},
      );
    });
    
    // Device info endpoint
    router.get('/device', (Request req) async {
      return Response.ok(jsonEncode({
        'platform': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'processors': Platform.numberOfProcessors,
      }), headers: {'content-type': 'application/json'});
    });
    
    // Metrics endpoint for thermal characterization
    router.get('/metrics', (Request req) async {
      return Response.ok(jsonEncode({
        'timestamp': DateTime.now().toIso8601String(),
        'memory_used_mb': ProcessInfo.currentRss ~/ (1024 * 1024),
        'inference_count': _inferenceCount,
        'last_inference_ms': _lastInferenceMs,
      }), headers: {'content-type': 'application/json'});
    });
    
    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router);
    
    _server = await shelf_io.serve(handler, '0.0.0.0', port);
    debugPrint('Eval server running on port $port');
  }
  
  Future<void> stop() async {
    await _server?.close(force: true);
  }
}
```

### Afternoon (2 hours)
**Wire eval server into `main.dart`**

Agent 1 already created the eval mode detection in `mobile/lib/core/utils/eval_mode.dart`. Import and use it:

```dart
import 'package:civic_lens/core/utils/eval_mode.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (kEvalMode) {
    final inferenceService = InferenceService();
    await inferenceService.initialize();
    final evalServer = EvalServer(inferenceService);
    await evalServer.start();
    debugPrint('Running in eval mode — server on :8080');
  }
  
  runApp(const CivicLensApp());
}
```

**Note:** `kEvalMode` is already defined as `const bool.fromEnvironment('EVAL_MODE', defaultValue: false)`. Don't redefine it.

**Add `inferRaw()` to the inference service**

Find the existing inference service (likely `InferenceService` or similar in `mobile/lib/`). Add this method:

```dart
Future<String?> inferRaw({
  required Uint8List imageBytes,
  required String prompt,
  double temperature = 0.0,
  int? tokenBudget,
}) async {
  final response = await _llamaClient.chatWithImages(
    prompt: prompt,
    images: [imageBytes],
    temperature: temperature,
    maxTokens: 2048,
    visualTokenBudget: tokenBudget,
  );
  return response.rawText;
}
```

**Note:** If the service has a different name or structure, adapt accordingly. The key is exposing raw inference with temperature and token budget controls.

**Test locally:**
```bash
./mobile/scripts/dev_deploy.sh --eval
# Verify server starts, check logs for "Eval server running on port 8080"
```

---

## Tuesday: Mac-Side Runner + Ground Truth

### Morning (3 hours)
**Create `research/eval/` directory structure**

```
research/eval/
├── runner.py          # Main experiment runner
├── results/           # JSONL output (gitignored)
├── README.md          # Usage documentation
└── requirements.txt   # Python dependencies
```

**Create `research/eval/requirements.txt`**

```
requests>=2.28.0
```

**Implement ground truth loader in `runner.py`**

```python
def load_ground_truth() -> dict[str, dict[str, str]]:
    """Load ground truth from spike artifacts."""
    gt = defaultdict(dict)
    ground_truth_path = SPIKE_DIR / 'artifacts' / 'clean' / 'html' / 'ground_truth.csv'
    with open(ground_truth_path) as f:
        for row in csv.DictReader(f):
            gt[row['artifact_id']][row['field_name']] = row['expected_value']
    return dict(gt)
```

**Implement image loader:**

```python
def load_image_b64(artifact_id: str, variant: str) -> str:
    """Load image and return base64-encoded string."""
    if variant == 'clean':
        path = ARTIFACTS_CLEAN / f"{artifact_id}-clean.pdf"
        if not path.exists():
            path = ARTIFACTS_CLEAN / f"{artifact_id}-clean.jpg"
    else:
        path = ARTIFACTS_DEGRADED / f"{artifact_id}-{variant}.jpg"
    
    if not path.exists():
        raise FileNotFoundError(f"Artifact not found: {path}")
    
    with open(path, 'rb') as f:
        return base64.b64encode(f.read()).decode()
```

### Afternoon (2 hours)
**Implement prompt builder:**

```python
def build_prompt(artifact_id: str, gt: dict, track: str) -> str:
    fields = gt.get(artifact_id, {})
    field_json = '\n'.join([f'  "{k}": "",' for k in fields.keys()])
    return f"""You are a document analysis assistant. Read the document carefully.

Rules:
- Extract only values clearly present in the document
- Read each field directly from its labeled location
- For pay-stub income: use current-period column only, not YTD
- Copy names character-by-character as printed
- If you cannot read a field, set its value to UNREADABLE
- Return ONLY valid JSON with exactly these keys. No markdown.

{{{field_json}
}}}"""
```

**Implement scoring functions:**

```python
def normalize(v: str) -> str:
    return v.lower().strip().replace(',', '').replace('$', '').replace(' ', '')

def score_field(extracted, expected: str) -> dict:
    if extracted is None or (isinstance(extracted, str) and not extracted.strip()):
        return {'score': 0, 'label': 'missing'}
    ext_n = normalize(str(extracted))
    exp_n = normalize(expected)
    if ext_n == 'unreadable':
        return {'score': 0, 'label': 'unreadable'}
    if ext_n == exp_n:
        return {'score': 2, 'label': 'exact'}
    if exp_n in ext_n or ext_n in exp_n:
        return {'score': 1, 'label': 'partial'}
    return {'score': -1, 'label': 'hallucinated'}
```

---

## Wednesday: Inference Loop + Summary Stats

### Morning (3 hours)
**Implement single inference call:**

```python
def run_inference(
    image_b64: str,
    prompt: str,
    track: str,
    temperature: float = 0.0,
    token_budget: int | None = None,
    timeout: int = 120,
) -> dict:
    payload = {
        'image': image_b64,
        'prompt': prompt,
        'track': track,
        'temperature': temperature,
    }
    if token_budget is not None:
        payload['token_budget'] = token_budget
    
    t0 = time.time()
    try:
        r = requests.post(f"{PHONE_URL}/infer", json=payload, timeout=timeout)
        r.raise_for_status()
        data = r.json()
        return {
            'response': data.get('response', ''),
            'elapsed_ms': data.get('elapsed_ms', int((time.time() - t0) * 1000)),
            'parse_ok': bool(data.get('response', '').strip()),
            'error': None,
        }
    except requests.exceptions.Timeout:
        return {'response': '', 'elapsed_ms': timeout * 1000, 'parse_ok': False, 'error': 'timeout'}
    except Exception as e:
        return {'response': '', 'elapsed_ms': 0, 'parse_ok': False, 'error': str(e)}
```

**Implement experiment runner with thermal cooldown:**

```python
def run_experiment(
    artifact_id: str,
    variant: str,
    track: str,
    n_runs: int,
    temperature: float,
    token_budget: int | None,
    gt: dict,
    cooldown_s: float = 2.0,
) -> list[dict]:
    image_b64 = load_image_b64(artifact_id, variant)
    prompt = build_prompt(artifact_id, gt, track)
    fields = gt.get(artifact_id, {})
    
    results = []
    for i in range(n_runs):
        print(f"  {artifact_id} {variant} temp={temperature} budget={token_budget} "
              f"run {i+1}/{n_runs}", end='\r', flush=True)
        
        infer_result = run_inference(image_b64, prompt, track, temperature, token_budget)
        parsed = parse_with_retry(infer_result['response'])
        
        field_scores = {}
        if parsed and fields:
            for fname, expected in fields.items():
                field_scores[fname] = score_field(parsed.get(fname), expected)
        
        pts = [s['score'] for s in field_scores.values()]
        avg_score = sum(pts) / len(pts) if pts else None
        halluc_count = sum(1 for s in field_scores.values() if s['label'] == 'hallucinated')
        
        record = {
            'artifact_id': artifact_id,
            'variant': variant,
            'track': track,
            'run': i,
            'temperature': temperature,
            'token_budget': token_budget,
            'elapsed_ms': infer_result['elapsed_ms'],
            'parse_ok': parsed is not None,
            'error': infer_result['error'],
            'raw_response': infer_result['response'],
            'field_scores': field_scores,
            'avg_score': round(avg_score, 4) if avg_score is not None else None,
            'hallucination_count': halluc_count,
        }
        results.append(record)
        
        if i < n_runs - 1:
            time.sleep(cooldown_s)
    
    print()
    return results
```

### Afternoon (2 hours)
**Implement summary statistics:**

```python
def compute_summary(results: list[dict]) -> dict:
    scored = [r for r in results if r['avg_score'] is not None]
    if not scored:
        return {}
    
    scores = [r['avg_score'] for r in scored]
    latencies = [r['elapsed_ms'] for r in results if r['elapsed_ms']]
    all_labels = [s['label'] for r in scored for s in r['field_scores'].values()]
    
    n_fields = len(all_labels)
    
    return {
        'n_runs': len(results),
        'n_scored': len(scored),
        'parse_ok_rate': sum(1 for r in results if r['parse_ok']) / len(results),
        'avg_score_mean': sum(scores) / len(scores),
        'avg_score_std': (sum((s - sum(scores)/len(scores))**2 for s in scores) / len(scores)) ** 0.5,
        'hallucination_rate': all_labels.count('hallucinated') / n_fields if n_fields else 0,
        'exact_rate': all_labels.count('exact') / n_fields if n_fields else 0,
        'missing_rate': all_labels.count('missing') / n_fields if n_fields else 0,
        'unreadable_rate': all_labels.count('unreadable') / n_fields if n_fields else 0,
        'latency_mean_ms': sum(latencies) / len(latencies) if latencies else 0,
        'latency_p95_ms': sorted(latencies)[int(len(latencies) * 0.95)] if latencies else 0,
        'latency_std_ms': (sum((l - sum(latencies)/len(latencies))**2 for l in latencies) / len(latencies)) ** 0.5 if latencies else 0,
    }
```

**Implement CLI argument parsing and main loop** (see product plan for full implementation).

---

## Thursday: First Monte Carlo Run + Token Budget Ablation

### Morning (3 hours)
**First full experiment: D01/D03 Track A**

```bash
# Set phone IP (find via Settings > Wi-Fi > (i) next to network)
export PHONE_IP=192.168.1.X

# Verify connectivity
curl http://$PHONE_IP:8080/health

# Run 20-run experiment
python research/eval/runner.py \
  --artifacts D01,D03 \
  --track a \
  --variants clean,degraded \
  --runs 20 \
  --temp 0.0 \
  --cooldown 2.0 \
  --out research/eval/results/d01_d03_baseline.jsonl
```

Expected output metrics:
- `avg_score_mean` — overall accuracy
- `hallucination_rate` — false positive rate
- `latency_mean_ms` / `latency_p95_ms` — timing
- `parse_ok_rate` — JSON parsing success

### Afternoon (2 hours)
**Visual token budget ablation**

```bash
python research/eval/runner.py \
  --artifacts D03 \
  --track a \
  --variants clean,degraded \
  --runs 10 \
  --temp 0.0 \
  --token-budgets 70,140,280,560,1120 \
  --ablation \
  --cooldown 3.0 \
  --out research/eval/results/token_budget_ablation.jsonl
```

**Expected finding:** Accuracy improves with higher token budgets on document-dense artifacts, with diminishing returns above 560. Latency increases roughly linearly.

**Document results** in `research/eval/README.md`.

---

## Friday: Thermal Characterization + Documentation

### Morning (3 hours)
**Thermal characterization**

Add metrics polling to runner:

```python
def poll_metrics_during_experiment(duration_s: int, interval_s: int = 30):
    """Poll /metrics endpoint during long experiments."""
    metrics_log = []
    start = time.time()
    while time.time() - start < duration_s:
        try:
            r = requests.get(f"{PHONE_URL}/metrics", timeout=5)
            metrics_log.append(r.json())
        except:
            pass
        time.sleep(interval_s)
    return metrics_log
```

Plot inference latency vs inference count to detect thermal throttling.

Run extended experiment:
```bash
python research/eval/runner.py \
  --artifacts D01,D03,D04 \
  --track a \
  --runs 30 \
  --temp 0.0 \
  --cooldown 1.0 \
  --out research/eval/results/thermal_test.jsonl
```

### Afternoon (2 hours)
**Documentation and handoff**

Create `research/eval/README.md`:

```markdown
# CivicLens Evaluation Harness

## Quick start

```bash
# 1. Start app in eval mode on iPhone
./mobile/scripts/dev_deploy.sh --eval

# 2. Set phone IP
export PHONE_IP=192.168.1.X

# 3. Run experiment
python runner.py --artifacts D01,D03 --track a --runs 20
```

## Experiments run this week

| Experiment | Date | Results File | Key Finding |
|------------|------|--------------|-------------|
| D01/D03 baseline | [date] | d01_d03_baseline.jsonl | ... |
| Token budget ablation | [date] | token_budget_ablation.jsonl | ... |
```

**Handoff to Agent 4:**
Share summary statistics for Kaggle writeup:
- Accuracy numbers (exact, partial, hallucination rates)
- Latency measurements (mean, p95)
- Token budget ablation findings

---

## Acceptance Criteria

- [ ] Eval server starts when app launched with `EVAL_MODE=true`
- [ ] `/health` endpoint reachable from Mac on same WiFi
- [ ] `/infer` endpoint handles single image + prompt, returns response + timing
- [ ] `/metrics` endpoint returns memory and inference count
- [ ] Mac-side runner connects, sends test request, gets valid response
- [ ] 20-run D01/D03 experiment completes unattended, results saved to JSONL
- [ ] Token budget ablation script runs and produces results
- [ ] Results include all required fields (field_scores, avg_score, hallucination_count)
- [ ] `research/eval/README.md` documents usage and findings

---

## Integration Points

| Handoff | To | When | What |
|---------|-----|------|------|
| Eval server IP + confirmation | All agents | Tuesday | Reference for testing |
| First Monte Carlo results | Agent 4 | Thursday | Accuracy/latency numbers for writeup |
| Token budget findings | Agent 4 | Friday | Ablation results for Kaggle writeup |
| Eval infrastructure | Future weeks | Ongoing | Foundation for paper experiments |
