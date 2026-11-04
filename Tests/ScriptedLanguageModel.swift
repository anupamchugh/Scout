//
//  ScriptedLanguageModel.swift
//  ScoutTests
//
//  Copied from the owner's SurfCoach (App/iOSTests/ScriptedLanguageModel.swift, commit 97cf56a).
//
import Foundation
import FoundationModels
import Synchronization

/// A language model that follows a script instead of weights, so a unit test can run a whole chat
/// turn (profile, history transform, streaming, overflow recovery) without the on-device model.
/// It records every request and every prewarm it receives.
final class ModelScript: Sendable {
    struct Request: Sendable {
        let transcript: [Transcript.Entry]

        var prompts: [String] {
            transcript.compactMap { entry in
                guard case .prompt(let prompt) = entry else { return nil }
                return ModelScript.text(of: prompt.segments)
            }
        }
    }

    enum Reply: Sendable {
        /// Writes text in these pieces.
        case write([String])
        /// Refuses the request as too long for the context window, as the on-device model does.
        case overflow
    }

    private struct State {
        var requests: [Request] = []
        var prewarms = 0
    }

    private let state = Mutex(State())
    private let behavior: @Sendable (_ index: Int, _ request: Request) -> Reply

    init(_ behavior: @escaping @Sendable (_ index: Int, _ request: Request) -> Reply) { self.behavior = behavior }

    /// Answers every request with `text`, overflowing the requests whose 0-based index is in `overflowing`.
    static func answering(_ text: String, overflowing: Set<Int> = []) -> ModelScript {
        ModelScript { index, _ in overflowing.contains(index) ? .overflow : .write([text]) }
    }

    var requests: [Request] { state.withLock { $0.requests } }
    var prewarms: Int { state.withLock { $0.prewarms } }

    func reply(to request: Request) -> Reply {
        let index = state.withLock { state in
            state.requests.append(request)
            return state.requests.count - 1
        }
        return behavior(index, request)
    }

    func markPrewarm() { state.withLock { $0.prewarms += 1 } }

    static func text(of segments: [Transcript.Segment]) -> String {
        segments.reduce(into: "") { result, segment in
            if case .text(let text) = segment { result += text.content }
        }
    }

    // An executor is built from a hashable configuration, so scripts are found by id.
    private static let scripts = Mutex<[UUID: ModelScript]>([:])

    func register() -> UUID {
        let id = UUID()
        Self.scripts.withLock { $0[id] = self }
        return id
    }

    static func script(_ id: UUID) -> ModelScript? { scripts.withLock { $0[id] } }
}

struct ScriptedLanguageModel: LanguageModel {
    typealias Executor = ScriptedExecutor
    let scriptID: UUID

    init(_ script: ModelScript) { scriptID = script.register() }

    var capabilities: LanguageModelCapabilities { LanguageModelCapabilities([.toolCalling]) }
    var executorConfiguration: ScriptedExecutor.Configuration { .init(scriptID: scriptID) }
}

struct ScriptedExecutor: LanguageModelExecutor {
    typealias Model = ScriptedLanguageModel
    struct Configuration: Hashable, Sendable { let scriptID: UUID }

    private let script: ModelScript

    init(configuration: Configuration) throws {
        guard let script = ModelScript.script(configuration.scriptID) else {
            throw LanguageModelError.timeout(.init(debugDescription: "no script"))
        }
        self.script = script
    }

    func prewarm(model: ScriptedLanguageModel, transcript: Transcript) {
        script.markPrewarm()
    }

    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: ScriptedLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        switch script.reply(to: ModelScript.Request(transcript: Array(request.transcript))) {
        case .write(let pieces):
            for piece in pieces {
                await channel.send(.response(action: .appendText(piece, tokenCount: max(1, piece.count / 3))))
            }
        case .overflow:
            throw LanguageModelError.contextSizeExceeded(.init(
                contextSize: 4_096, tokenCount: 4_200, debugDescription: "scripted overflow"
            ))
        }
    }
}
