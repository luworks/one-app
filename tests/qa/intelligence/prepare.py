#!/usr/bin/env python3
"""Prepare the owned, isolated simulator sample. Does not build or run it."""
import argparse
import base64
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def replace_section(path, marker, text):
    original = path.read_text().split(marker)[0]
    path.write_text(original.rstrip() + '\n\n' + marker + '\n' + text)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sample', type=Path, required=True)
    args = parser.parse_args()
    sample = args.sample.resolve()
    # Explicit path, expected owned source layout, and no writes to the Today app.
    state = sample / 'examples/llama.swiftui/llama.swiftui/Models/LlamaState.swift'
    library = sample / 'examples/llama.swiftui/llama.cpp.swift/LibLlama.swift'
    view = sample / 'examples/llama.swiftui/llama.swiftui/UI/ContentView.swift'
    if not state.is_file() or not library.is_file() or not view.is_file():
        raise SystemExit('Expected the retained llama.cpp simulator sample')
    fixtures = {}
    hashes = {}
    for split, name in [('development', 'ai-chat-capability-eval.json'),
                        ('holdout', 'intelligence-model-selection-holdout.json')]:
        raw = (ROOT / 'tests/fixtures' / name).read_bytes()
        hashes[split] = hashlib.sha256(raw).hexdigest()
        fixtures[split] = json.loads(raw)['cases']
    data = json.dumps(fixtures, ensure_ascii=False, separators=(',', ':')).encode()
    source = Path(__file__).with_name('Batch.swift').read_text()
    start = source.index('extension LlamaContext {')
    end = source.index('extension LlamaState {')
    qwen = source[start:end]
    rest = source[:start] + source[end:]
    state_text = state.read_text().split('// BEGIN OWNED BATCH EVALUATION')[0]
    if '@Published var evaluationRunning' not in state_text:
        state_text = state_text.replace('    private var llamaContext:',
            '    @Published var evaluationRunning = false\n'
            '    private var activeEvaluationModel = "unloaded"\n'
            '    private var llamaContext:', 1)
        state_text = state_text.replace('            messageLog += "Loaded model',
            '            activeEvaluationModel = modelUrl.lastPathComponent\n'
            '            messageLog += "Loaded model', 1)
    state.write_text(state_text)
    constants = '\nlet evaluationFixtureBase64 = "' + base64.b64encode(data).decode() + '"\n'
    constants += 'let evaluationFixtureHash = "' + hashlib.sha256(data).hexdigest() + '"\n'
    deadline = (ROOT / 'ios/Sources/TodayCore/AsyncDeadline.swift').read_text()
    replace_section(state, '// BEGIN OWNED BATCH EVALUATION', rest + constants + deadline)
    replace_section(library, '// BEGIN OWNED BATCH EVALUATION', qwen)
    text = view.read_text()
    if 'Run Apple dev' in text and 'Probe Apple' not in text:
        text = text.replace('                HStack {\n                    Button("Run Apple dev")',
            '                HStack {\n'
            '                    Button("Probe Apple") { Task { await llamaState.runEvaluation(apple: true, smoke: true) } }\n'
            '                    Button("Probe Qwen") { Task { await llamaState.runEvaluation(apple: false, smoke: true) } }\n'
            '                }.disabled(llamaState.evaluationRunning)\n'
            '                HStack {\n                    Button("Run Apple dev")', 1)
        view.write_text(text)
    if 'Run Apple dev' not in text:
        text = text.replace('                NavigationLink(destination: DrawerView',
            '                HStack {\n'
            '                    Button("Probe Apple") { Task { await llamaState.runEvaluation(apple: true, smoke: true) } }\n'
            '                    Button("Probe Qwen") { Task { await llamaState.runEvaluation(apple: false, smoke: true) } }\n'
            '                }.disabled(llamaState.evaluationRunning)\n'
            '                HStack {\n'
            '                    Button("Run Apple dev") { Task { await llamaState.runEvaluation(apple: true) } }\n'
            '                    Button("Run Qwen dev") { Task { await llamaState.runEvaluation(apple: false) } }\n'
            '                }.disabled(llamaState.evaluationRunning)\n'
            '                HStack {\n'
            '                    Button("Apple holdout") { Task { await llamaState.runEvaluation(apple: true, holdout: true) } }\n'
            '                    Button("Qwen holdout") { Task { await llamaState.runEvaluation(apple: false, holdout: true) } }\n'
            '                }.disabled(llamaState.evaluationRunning)\n'
            '                NavigationLink(destination: DrawerView', 1)
        view.write_text(text)
    if 'Native Apple dev' not in text:
        text = text.replace('                NavigationLink(destination: DrawerView',
            '                HStack {\n'
            '                    Button("Probe native Apple") { Task { await llamaState.runEvaluation(apple: true, smoke: true, native: true) } }\n'
            '                    Button("Native Apple dev") { Task { await llamaState.runEvaluation(apple: true, native: true) } }\n'
            '                }.disabled(llamaState.evaluationRunning)\n'
            '                NavigationLink(destination: DrawerView', 1)
        view.write_text(text)
    print(json.dumps({'fixture_hashes': hashes, 'bundled_sha256': hashlib.sha256(data).hexdigest(),
                      'development_cases': len(fixtures['development']),
                      'holdout_cases': len(fixtures['holdout'])}, indent=2))


if __name__ == '__main__':
    main()
