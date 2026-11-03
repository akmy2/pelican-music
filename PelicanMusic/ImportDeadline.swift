import Foundation

struct ImportTimeout: LocalizedError {
    let stage: String
    var errorDescription: String? { "Tempo de espera esgotado: \(stage). Se o arquivo estiver na nuvem, baixe-o no app Arquivos e tente novamente." }
}

// Unstructured worker: returning after a deadline must not wait for a provider
// or AVFoundation operation that ignores cooperative task cancellation.
enum ImportDeadline {
    static func run<Value>(seconds: Double, stage: String, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let race = ImportRace<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.install(continuation)
                let worker = Task.detached {
                    do { let value = try await operation(); try Task.checkCancellation(); race.finish(.success(value)) }
                    catch { race.finish(.failure(error)) }
                }
                race.attach(worker)
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                    if race.finish(.failure(ImportTimeout(stage: stage))) { race.cancelWorker() }
                }
            }
        } onCancel: { race.cancel() }
    }
}

private final class ImportRace<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var worker: Task<Void, Never>?
    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func attach(_ worker: Task<Void, Never>) {
        lock.lock(); self.worker = worker; let completed = result != nil; lock.unlock()
        if completed { worker.cancel() }
    }
    @discardableResult func finish(_ result: Result<Value, Error>) -> Bool {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return false }
        self.result = result; let continuation = self.continuation; self.continuation = nil
        lock.unlock(); continuation?.resume(with: result); return true
    }
    func cancelWorker() { lock.lock(); let worker = worker; lock.unlock(); worker?.cancel() }
    func cancel() { finish(.failure(CancellationError())); cancelWorker() }
}
