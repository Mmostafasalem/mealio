import XCTest
@testable import smartmarket

/// The offline model's download, with Hugging Face replaced by a stand-in.
/// TestFlight: the download "didn't finish" and Try again did nothing. A
/// finished download was judged by the screen's state (still "downloading")
/// instead of the files, so it always failed, and every retry found the files
/// already there and failed the same way at once.
@MainActor
final class OfflineSpeechModelTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-speech-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("parakeet-v3", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    /// A stand-in installer: `script` decides what each attempt does.
    @MainActor private final class FakeHub {
        var attempts = 0
        var installed = false
        var freeSpace: Int64? = 10_000_000_000
        var script: @MainActor (Int, URL, @escaping @Sendable (OfflineSpeechModel.Installer.Step) -> Void) async throws -> Void = { _, _, _ in }

        var installer: OfflineSpeechModel.Installer {
            OfflineSpeechModel.Installer(
                isSupported: true,
                isInstalled: { [unowned self] _ in self.installed },
                download: { [unowned self] folder, step in
                    self.attempts += 1
                    try await self.script(self.attempts, folder, step)
                },
                freeSpace: { [unowned self] _ in self.freeSpace }
            )
        }
    }

    private func model(_ hub: FakeHub) -> OfflineSpeechModel {
        OfflineSpeechModel(installer: hub.installer, folder: folder, watchesApp: false)
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 3) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// Writes a half-downloaded file where FluidAudio would.
    private func writePartial() throws -> URL {
        let bundle = folder.deletingLastPathComponent().appendingPathComponent("parakeet-tdt-0.6b-v3-coreml/Encoder.mlmodelc/weights", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let partial = bundle.appendingPathComponent("weight.bin.partial")
        try Data(repeating: 7, count: 4096).write(to: partial)
        return partial
    }

    func testAFinishedDownloadIsReady() async {
        let hub = FakeHub()
        hub.script = { _, _, step in
            step(.downloading(0.4))
            step(.downloading(1))
            step(.preparing)
            hub.installed = true
        }
        let offline = model(hub)
        XCTAssertEqual(offline.state, .notDownloaded)
        offline.startDownload()
        XCTAssertEqual(offline.state, .downloading(0))
        await waitUntil { offline.state == .ready }
        XCTAssertEqual(offline.state, .ready, "a finished download must not be reported as unfinished")
        XCTAssertNil(offline.lastFailure)
    }

    func testFailedThenTryAgainDownloadsAgain() async throws {
        let hub = FakeHub()
        hub.script = { attempt, _, step in
            if attempt == 1 { throw URLError(.networkConnectionLost) }
            step(.downloading(0.5))
            hub.installed = true
        }
        let offline = model(hub)
        offline.startDownload()
        await waitUntil { if case .failed = offline.state { return true } else { return false } }
        XCTAssertEqual(offline.lastFailure, .interrupted)
        XCTAssertEqual(offline.state, .failed(OfflineSpeechModel.Failure.interrupted.message))

        // Try again: straight back to downloading, a second real attempt, then ready.
        offline.startDownload()
        XCTAssertEqual(offline.state, .downloading(0))
        await waitUntil { offline.state == .ready }
        XCTAssertEqual(hub.attempts, 2)
        XCTAssertEqual(offline.state, .ready)
    }

    func testTryAgainWhileStuckStartsAFreshAttempt() async {
        let hub = FakeHub()
        hub.script = { attempt, _, _ in
            if attempt == 1 {
                // Hangs until cancelled, like a frozen connection.
                while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
                throw CancellationError()
            }
            hub.installed = true
        }
        let offline = model(hub)
        offline.startDownload()
        await waitUntil { hub.attempts == 1 }
        offline.startDownload()
        await waitUntil { offline.state == .ready }
        XCTAssertEqual(hub.attempts, 2)
        XCTAssertEqual(offline.state, .ready, "the cancelled first attempt must not overwrite the second")
    }

    func testPartialFilesAreKeptToResumeAfterADroppedConnection() async throws {
        let hub = FakeHub()
        hub.script = { _, _, _ in throw URLError(.notConnectedToInternet) }
        let offline = model(hub)
        let partial = try writePartial()
        offline.startDownload()
        await waitUntil { offline.lastFailure != nil }
        XCTAssertEqual(offline.lastFailure, .noConnection)
        XCTAssertTrue(FileManager.default.fileExists(atPath: partial.path), "bytes already downloaded are kept for the next try")
    }

    func testDamagedFilesAreClearedBeforeTheNextTry() async throws {
        let hub = FakeHub()
        var sawPartialOnRetry: Bool?
        hub.script = { attempt, folder, _ in
            if attempt == 1 {
                // The download "finishes" but leaves an incomplete model behind.
                return
            }
            sawPartialOnRetry = FileManager.default.fileExists(
                atPath: folder.deletingLastPathComponent().appendingPathComponent("parakeet-tdt-0.6b-v3-coreml/Encoder.mlmodelc/weights/weight.bin.partial").path)
            hub.installed = true
        }
        let offline = model(hub)
        let partial = try writePartial()
        offline.startDownload()
        await waitUntil { offline.lastFailure != nil }
        XCTAssertEqual(offline.lastFailure, .corrupt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path), "an incomplete model is deleted")
        offline.startDownload()
        await waitUntil { offline.state == .ready }
        XCTAssertEqual(sawPartialOnRetry, false)
        XCTAssertEqual(offline.state, .ready)
    }

    func testNotEnoughSpaceSaysSoBeforeDownloading() async {
        let hub = FakeHub()
        hub.freeSpace = 100_000_000
        let offline = model(hub)
        offline.startDownload()
        XCTAssertEqual(offline.lastFailure, .notEnoughSpace)
        XCTAssertEqual(hub.attempts, 0)
        if case .failed(let message) = offline.state {
            XCTAssertTrue(message.contains("space"), message)
        } else {
            XCTFail("expected a failure, got \(offline.state)")
        }
        // Space freed: Try again works.
        hub.freeSpace = 10_000_000_000
        hub.script = { _, _, _ in hub.installed = true }
        offline.startDownload()
        await waitUntil { offline.state == .ready }
        XCTAssertEqual(offline.state, .ready)
    }

    func testProgressOnlyMovesForward() async {
        let hub = FakeHub()
        let release = AsyncStream<Void>.makeStream()
        hub.script = { _, _, step in
            step(.downloading(0.6))
            step(.downloading(0.2))   // a later file starts again from zero
            for await _ in release.stream { break }
            hub.installed = true
        }
        let offline = model(hub)
        offline.startDownload()
        await waitUntil { offline.state == .downloading(0.6) }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(offline.state, .downloading(0.6))
        release.continuation.yield()
        await waitUntil { offline.state == .ready }
        XCTAssertEqual(offline.state, .ready)
    }

    func testCancelRemovesEverything() async throws {
        let hub = FakeHub()
        hub.script = { _, _, _ in
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
            throw CancellationError()
        }
        let offline = model(hub)
        let partial = try writePartial()
        offline.startDownload()
        await waitUntil { hub.attempts == 1 }
        offline.cancelDownload()
        XCTAssertEqual(offline.state, .notDownloaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(offline.state, .notDownloaded, "the cancelled attempt reports nothing afterwards")
    }

    func testAlreadyOnThePhoneIsReadyAtOnce() {
        let hub = FakeHub()
        hub.installed = true
        let offline = model(hub)
        XCTAssertEqual(offline.state, .ready)
        offline.startDownload()
        XCTAssertEqual(offline.state, .ready)
        XCTAssertEqual(hub.attempts, 0)
    }

    func testErrorsGiveSpecificMessages() {
        typealias Failure = OfflineSpeechModel.Failure
        XCTAssertEqual(OfflineSpeechModel.failure(for: URLError(.notConnectedToInternet)), .noConnection)
        XCTAssertEqual(OfflineSpeechModel.failure(for: URLError(.notConnectedToInternet), inBackground: true), .interrupted)
        XCTAssertEqual(OfflineSpeechModel.failure(for: URLError(.networkConnectionLost)), .interrupted)
        XCTAssertEqual(OfflineSpeechModel.failure(for: URLError(.timedOut)), .tooSlow)
        XCTAssertEqual(OfflineSpeechModel.failure(for: NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)), .notEnoughSpace)
        XCTAssertEqual(OfflineSpeechModel.failure(for: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))), .notEnoughSpace)
        XCTAssertEqual(OfflineSpeechModel.failure(for: NSError(domain: "HTTP", code: 503)), .server(503))
        let wrapped = NSError(domain: "Outer", code: 1, userInfo: [NSUnderlyingErrorKey: URLError(.notConnectedToInternet) as NSError])
        XCTAssertEqual(OfflineSpeechModel.failure(for: wrapped), .noConnection)
        XCTAssertEqual(OfflineSpeechModel.failure(for: NSError(domain: "Other", code: 9)), .other)
        // Every message is different, and only network trouble keeps the partial files.
        let all: [Failure] = [.noConnection, .interrupted, .tooSlow, .notEnoughSpace, .server(500), .corrupt, .other]
        XCTAssertEqual(Set(all.map(\.message)).count, all.count)
        XCTAssertEqual(all.filter(\.keepsPartialFiles), [.noConnection, .interrupted, .tooSlow, .server(500)])
    }

    /// The real model's files are where `AsrModels` looks for them.
    func testTheRealModelFolderIsStable() {
        XCTAssertEqual(OfflineSpeechModel.directory.lastPathComponent, "parakeet-v3")
        XCTAssertEqual(OfflineSpeechModel.directory.deletingLastPathComponent().lastPathComponent, "OfflineSpeech")
    }
}
