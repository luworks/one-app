// Synthetic simulator evaluation only. Appended to the isolated llama.cpp sample.
import FoundationModels
import CryptoKit
import os

// Separate diagnostic: native schema generation, never pooled with raw-JSON results.
@Generable
enum EvalIntent: String, Codable { case chat, reminder, event, alarm, edit, clarify }
@Generable
enum EvalRepeat: String, Codable { case once, daily, weekdays, weekly, monthly, yearly }
@Generable
struct EvalNativeItem: Codable {
    var intent: EvalIntent
    var reply: String
    var title: String
    var date: String?
    var time: String?
    var `repeat`: EvalRepeat
    var weekdays: [Int]
    var duration_minutes: Int?
    var target: String?
}
@Generable
struct EvalNativePlan: Codable {
    var intent: EvalIntent
    var reply: String
    var title: String
    var date: String?
    var time: String?
    var `repeat`: EvalRepeat
    var weekdays: [Int]
    var duration_minutes: Int?
    var target: String?
    var items: [EvalNativeItem]?
}

struct EvalGeneration: Codable, Sendable {
    var output: String
    var status: String
    var elapsed_ms: Double
    var first_output_ms: Double?
    var generated_tokens: Int?
}

enum EvalFailure: Error { case decode(Int32), context, emptyPrompt }

extension LlamaContext {
    func evaluate(_ prompt: String, outputLimit: Int = 384, deadlineSeconds: Double = 120) throws -> EvalGeneration {
        clear()
        let started = Date()
        let input = tokenize(text: prompt, add_bos: true)
        guard !input.isEmpty else { throw EvalFailure.emptyPrompt }
        guard input.count + outputLimit < Int(llama_n_ctx(context)) else {
            throw EvalFailure.context
        }
        let sampler = llama_sampler_init_greedy()
        defer { llama_sampler_free(sampler); clear() }
        for offset in stride(from: 0, to: input.count, by: 512) {
            llama_batch_clear(&batch)
            for i in offset..<min(offset + 512, input.count) {
                llama_batch_add(&batch, input[i], Int32(i), [0], i == input.count - 1)
            }
            let code = llama_decode(context, batch)
            guard code == 0 else { throw EvalFailure.decode(code) }
        }
        var bytes: [CChar] = []
        var first: Double?
        var generated = 0
        var status = "token_limit"
        for position in input.count..<(input.count + outputLimit) {
            if Date().timeIntervalSince(started) >= deadlineSeconds { status = "timeout"; break }
            let token = llama_sampler_sample(sampler, context, batch.n_tokens - 1)
            if llama_vocab_is_eog(vocab, token) { status = "success"; break }
            generated += 1
            bytes += token_to_piece(token: token)
            if first == nil && !bytes.isEmpty { first = Date().timeIntervalSince(started) * 1000 }
            llama_batch_clear(&batch)
            llama_batch_add(&batch, token, Int32(position), [0], true)
            let code = llama_decode(context, batch)
            guard code == 0 else { throw EvalFailure.decode(code) }
        }
        let output = String(decoding: bytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        if status == "success" && output.isEmpty { status = "empty" }
        return EvalGeneration(output: output, status: status,
            elapsed_ms: Date().timeIntervalSince(started) * 1000,
            first_output_ms: first, generated_tokens: generated)
    }
}

extension LlamaState {
    static let evaluationInstructions = """
    You interpret planner requests. Today is Wednesday 2026-10-28 09:00 in America/Los_Angeles.
    Existing synthetic items: qa-visit-1500 '[QA] dentist / follow-up / 复诊' today 15:00;
    qa-visit-1600 '[QA] dentist / follow-up / 复诊' today 16:00.
    Return ONE JSON object only, with fields: intent (chat, reminder, event, alarm, edit,
    clarify), reply, title, date (YYYY-MM-DD or null), time (24h HH:mm or null),
    repeat (once,daily,weekdays,weekly,monthly,yearly), weekdays (Sunday=1, array),
    duration_minutes (integer or null), target (existing id or null).
    Reply naturally and briefly in the user language. Extract an action only when requested;
    questions, quoted/reported speech and refusals are not creation requests. Use history
    to fill follow-up slots. Preserve the subject and requested recurrence. Never invent
    missing dates or times. Clarify material ambiguity with one focused question.
    For several separate requests, add an items array containing one object per request
    with the same fields; leave top-level intent as reminder and title empty.
    No tools or writes exist: propose fields, never claim a reminder was saved, changed,
    scheduled, or will actually fire. A reminder without recurrence means once.
    """

    func runEvaluation(apple: Bool, holdout: Bool = false, smoke: Bool = false, native: Bool = false, repetitionCount: Int = 1) async {
        guard !evaluationRunning else { return }
        guard apple || llamaContext != nil else { messageLog += "Load Qwen first\n"; return }
        evaluationRunning = true
        defer { evaluationRunning = false }
        let instructions = Self.evaluationInstructions
        let modelName = apple ? (native ? "apple-system-native-schema" : "apple-system") : activeEvaluationModel
        let deadlineSeconds = 120.0
        var modelHash = "system-managed-unexposed"
        if !apple {
            guard let file = try? FileHandle(forReadingFrom: getDocumentsDirectory()
                .appendingPathComponent(activeEvaluationModel)) else {
                messageLog += "Cannot verify loaded model file\n"; return
            }
            var digest = SHA256()
            do {
                while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                    digest.update(data: chunk)
                }
                try file.close()
            } catch {
                try? file.close()
                messageLog += "Model file verification failed: \(error)\n"; return
            }
            modelHash = digest.finalize().map { String(format: "%02x", $0) }.joined()
            let pinned = [
                "Qwen3.5-2B-Q4_K_M.gguf": "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223",
                "Qwen3.5-4B-Q4_K_M.gguf": "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4"
            ]
            guard pinned[activeEvaluationModel] == modelHash else {
                messageLog += "Loaded model hash does not match pinned artifact\n"; return
            }
        }
        let data = Data(base64Encoded: evaluationFixtureBase64)!
        let root = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let allCases = root[holdout ? "holdout" : "development"] as! [[String: Any]]
        let cases = smoke ? allCases.filter { ["capability-question", "slot-followup"].contains($0["id"] as! String) } : allCases
        let promptHash = SHA256.hash(data: Data(Self.evaluationInstructions.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let runID = UUID().uuidString
        let file = getDocumentsDirectory().appendingPathComponent("eval-\(runID).jsonl")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try! FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        let logger = Logger(subsystem: "com.luworks.today.eval", category: "batch")
        // Separate one-repetition batches allow shared-host release between repeats.
        let repetitions = smoke ? 1 : repetitionCount
        let expected = repetitions * cases.reduce(0) { $0 + ($1["turns"] as! [Any]).count }
        logger.notice("TODAY_EVAL_START \(runID, privacy: .public) expected=\(expected) smoke=\(smoke)")
        for repetition in 0..<repetitions {
            for test in cases {
                var history = ""
                let turns = test["turns"] as! [[String: Any]]
                for (turnIndex, turn) in turns.enumerated() {
                    let input = turn["input"] as! String
                    let prompt = "Previous conversation:\n\(history)\nLatest user:\n\(input)"
                    let started = Date()
                    var result: EvalGeneration
                    var attempted = false
                    var failure: String? = nil
                    do {
                        if apple {
                            guard case .available = SystemLanguageModel.default.availability else {
                                throw EvalUnavailable()
                            }
                            attempted = true
                            let output = try await AsyncDeadline.run(for: .seconds(deadlineSeconds)) {
                                let session = LanguageModelSession(instructions: instructions)
                                if native {
                                    let response = try await session.respond(to: prompt,
                                        generating: EvalNativePlan.self,
                                        options: GenerationOptions(temperature: 0, maximumResponseTokens: 384))
                                    let data = try JSONEncoder().encode(response.content)
                                    var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                                    // Codable omits nil optionals; preserve the shared JSON contract.
                                    for key in ["date", "time", "duration_minutes", "target"] where object[key] == nil {
                                        object[key] = NSNull()
                                    }
                                    let normalized = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                                    return String(decoding: normalized, as: UTF8.self)
                                }
                                return try await session.respond(to: prompt,
                                    options: GenerationOptions(temperature: 0, maximumResponseTokens: 384)).content
                            }
                            result = EvalGeneration(output: output,
                                status: output.isEmpty ? "empty" : "success",
                                elapsed_ms: Date().timeIntervalSince(started) * 1000,
                                first_output_ms: nil, generated_tokens: nil)
                        } else {
                            attempted = true
                            let formatted = "<|im_start|>system\n\(Self.evaluationInstructions)<|im_end|>\n<|im_start|>user\n\(prompt)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
                            result = try await llamaContext!.evaluate(formatted, deadlineSeconds: deadlineSeconds)
                        }
                    } catch {
                        failure = String(describing: error)
                        let status = error is EvalUnavailable ? "unavailable" :
                            (error is AsyncDeadline.TimedOut ? "timeout" : "error")
                        result = EvalGeneration(output: "", status: status,
                            elapsed_ms: Date().timeIntervalSince(started) * 1000,
                            first_output_ms: nil, generated_tokens: nil)
                    }
                    var row = (try! JSONSerialization.jsonObject(with: JSONEncoder().encode(result))) as! [String: Any]
                    row["error"] = failure
                    row.merge(["run": runID, "model": modelName, "split": holdout ? "holdout" : "development",
                        "case": test["id"]!, "repetition": repetition, "turn": turnIndex,
                        "smoke": smoke, "expected_records": expected,
                        "repetitions": repetitions,
                        "input": input, "attempted": attempted, "fallback": false,
                        "prompt_sha256": promptHash, "fixture_sha256": evaluationFixtureHash,
                        "model_sha256": modelHash,
                        "availability": String(describing: SystemLanguageModel.default.availability),
                        "output_limit": 384, "warm_policy": "preloaded_no_explicit_warmup",
                        "deadline_seconds": deadlineSeconds,
                        "generation_mode": native ? "native_schema" : "raw_json",
                        "os": ProcessInfo.processInfo.operatingSystemVersionString,
                        "deadline_granularity": apple ? "async_deadline" : "between_decode_calls"]) { _, new in new }
                    let encoded = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                    try! handle.write(contentsOf: encoded + Data([10]))
                    try! handle.synchronize()
                    // Unified logging escapes backslashes in raw JSON. Base64 preserves bytes.
                    let payload = Array(encoded.base64EncodedString().utf8)
                    let recordID = UUID().uuidString
                    let parts = (payload.count + 599) / 600
                    for part in 0..<parts {
                        let chunk = String(decoding: payload[(part * 600)..<min((part + 1) * 600, payload.count)], as: UTF8.self)
                        logger.notice("TODAY_EVAL_CHUNK \(recordID, privacy: .public) \(part) \(parts) \(chunk, privacy: .public)")
                    }
                    messageLog = "\(modelName) \(repetition + 1)/\(repetitions) \(test["id"]!) turn \(turnIndex + 1): \(result.status)\n\(file.lastPathComponent)"
                    history += "User: \(input)\nAssistant: \(result.output)\n"
                }
            }
        }
        messageLog += "\nEVALUATION COMPLETE \(runID)"
        logger.notice("TODAY_EVAL_COMPLETE \(runID, privacy: .public)")
    }
}

struct EvalUnavailable: Error {}
