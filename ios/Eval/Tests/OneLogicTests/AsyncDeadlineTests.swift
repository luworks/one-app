import Testing
@testable import TodayCore

@Suite(.timeLimit(.minutes(1)))
struct AsyncDeadlineTests {
    private enum Failure: Error { case expected }

    /// Deliberately ignores cancellation, just like a stalled model continuation.
    private actor Gate {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            await withCheckedContinuation { continuation in
                if opened { continuation.resume() }
                else { waiters.append(continuation) }
            }
        }
        func open() {
            opened = true
            let pending = waiters
            waiters = []
            for waiter in pending { waiter.resume() }
        }
    }

    @Test func returnsValueAndOptionalNil() async throws {
        #expect(try await AsyncDeadline.run(for: .seconds(30)) { 42 } == 42)
        let value: Int? = try await AsyncDeadline.run(for: .seconds(30)) { nil }
        #expect(value == nil)
    }

    @Test func propagatesOperationError() async {
        await #expect(throws: Failure.self) {
            try await AsyncDeadline.run(for: .seconds(30)) { () -> Int in throw Failure.expected }
        }
    }

    @Test func actualDurationTimerAbandonsUncooperativeWork() async {
        let started = Gate(), release = Gate(), exited = Gate()
        let task = Task {
            try await AsyncDeadline.run(for: .milliseconds(20)) {
                await started.open()
                await release.wait()
                await exited.open()
                return 99
            }
        }
        await started.wait()
        await #expect(throws: AsyncDeadline.TimedOut.self) { try await task.value }
        // The caller has returned while the worker is still suspended.
        await release.open()
        await exited.wait()
    }

    @Test func timeoutCancelsWorkerAndLateValueCannotWin() async throws {
        let started = Gate(), release = Gate(), expired = Gate()
        let workerCancelled = Gate(), exited = Gate()
        let task = Task {
            try await AsyncDeadline.run(timeout: {
                await expired.wait()
            }) {
                await withTaskCancellationHandler {
                    await started.open()
                    await release.wait()
                    await exited.open()
                    return 99
                } onCancel: { Task { await workerCancelled.open() } }
            }
        }
        await started.wait()
        await expired.open()
        await #expect(throws: AsyncDeadline.TimedOut.self) { try await task.value }
        await workerCancelled.wait()
        // A new request can finish before the abandoned request returns.
        #expect(try await AsyncDeadline.run(for: .seconds(30)) { 7 } == 7)
        await release.open()
        await exited.wait()
        await #expect(throws: AsyncDeadline.TimedOut.self) { try await task.value }
    }

    @Test func cancellationBeforeCallDoesNotStartWork() async {
        let enter = Gate()
        let task = Task {
            await enter.wait()
            return try await AsyncDeadline.run(for: .seconds(30)) {
                Issue.record("Cancelled request started work")
                return 1
            }
        }
        task.cancel()
        await enter.open()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func callerCancellationReleasesCallerAndCancelsWorkerAndTimer() async {
        let workerStarted = Gate(), timerStarted = Gate(), release = Gate()
        let workerCancelled = Gate(), timerCancelled = Gate(), exited = Gate()
        let task = Task {
            try await AsyncDeadline.run(timeout: {
                await withTaskCancellationHandler {
                    await timerStarted.open()
                    try? await Task.sleep(for: .seconds(60))
                } onCancel: { Task { await timerCancelled.open() } }
            }) {
                await withTaskCancellationHandler {
                    await workerStarted.open()
                    await release.wait()
                    await exited.open()
                    return 3
                } onCancel: { Task { await workerCancelled.open() } }
            }
        }
        await workerStarted.wait()
        await timerStarted.wait()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        await workerCancelled.wait()
        await timerCancelled.wait()
        await release.open()
        await exited.wait()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func successCancelsTimerAndLateCancellationPreservesValue() async throws {
        let timerStarted = Gate(), timerCancelled = Gate(), releaseTimer = Gate()
        let task = Task {
            try await AsyncDeadline.run(timeout: {
                await withTaskCancellationHandler {
                    await timerStarted.open()
                    await releaseTimer.wait()
                } onCancel: { Task { await timerCancelled.open() } }
            }) {
                await timerStarted.wait()
                return 5
            }
        }
        #expect(try await task.value == 5)
        await timerCancelled.wait()
        task.cancel()
        await releaseTimer.open()
        #expect(try await task.value == 5)
    }

    @Test func cancellingOneRequestDoesNotCancelSibling() async throws {
        let started = Gate(), release = Gate()
        let sibling = Task {
            try await AsyncDeadline.run(for: .seconds(30)) {
                await started.open()
                await release.wait()
                try Task.checkCancellation()
                return 8
            }
        }
        await started.wait()
        let cancelled = Task { try await AsyncDeadline.run(for: .seconds(30)) { 1 } }
        cancelled.cancel()
        _ = await cancelled.result
        await release.open()
        #expect(try await sibling.value == 8)
    }

    @Test func cancellationRacingContinuationAndTaskInstallation() async {
        for _ in 0..<100 {
            let enter = Gate()
            let task = Task {
                await enter.wait()
                return try await AsyncDeadline.run(for: .seconds(30)) { 13 }
            }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await enter.open() }
                group.addTask { task.cancel() }
            }
            switch await task.result {
            case .success(let value): #expect(value == 13)
            case .failure(let error): #expect(error is CancellationError)
            }
        }
    }

    @Test func simultaneousCompletionTimeoutAndCancellationResumeExactlyOnce() async {
        for _ in 0..<100 {
            let release = Gate(), workerStarted = Gate(), timerStarted = Gate()
            let workerExited = Gate(), timerExited = Gate()
            let task = Task {
                try await AsyncDeadline.run(timeout: {
                    await timerStarted.open()
                    await release.wait()
                    await timerExited.open()
                }) {
                    await workerStarted.open()
                    await release.wait()
                    await workerExited.open()
                    return 11
                }
            }
            await workerStarted.wait()
            await timerStarted.wait()
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await release.open() }
                group.addTask { task.cancel() }
            }
            switch await task.result {
            case .success(let value): #expect(value == 11)
            case .failure(let error): #expect(error is CancellationError || error is AsyncDeadline.TimedOut)
            }
            await workerExited.wait()
            await timerExited.wait()
        }
    }
}
