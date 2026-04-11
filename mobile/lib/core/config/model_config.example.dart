// Template for `model_config.dart`.
// Copy to model_config.dart or run: ./scripts/dev_deploy.sh (which regenerates it).
//
// iPhone must reach this host on the same LAN (use your Mac's IP, not localhost,
// when testing on device — dev_deploy.sh sets MODEL_SERVER_URL accordingly).

const String kModelDownloadUrl =
    'http://127.0.0.1:8888/gemma-4-E2B-it-Q4_K_M.gguf';
const String kModelFilename = 'gemma-4-E2B-it-Q4_K_M.gguf';
