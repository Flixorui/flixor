//
//  AIEngine.swift
//  FlixorMac
//
//  One way to ask a model for structured data, whichever engine the user
//  picked: Apple Intelligence on this Mac (FoundationModels), OpenAI or
//  Anthropic with the user's own key. Features describe the JSON they want
//  with `AISchema`; each engine turns that into its own schema format and
//  returns JSON matching it. Nothing here runs unless the master switch in
//  AISettings is on. Keys are never logged; requests log only status codes.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Schema

/// A small JSON schema that all three engines understand.
indirect enum AISchema {
    case object(name: String, properties: [AISchemaProperty])
    case string(choices: [String]? = nil)
    case integer
    case number
    case array(AISchema)

    /// JSON Schema for the cloud engines: every object closed, every property
    /// required, optional ones nullable (what strict structured outputs need).
    func jsonSchema() -> [String: Any] {
        switch self {
        case .object(_, let properties):
            var props: [String: Any] = [:]
            for property in properties {
                var schema = property.schema.jsonSchema()
                if let description = property.description { schema["description"] = description }
                props[property.name] = property.isOptional ? ["anyOf": [schema, ["type": "null"]]] : schema
            }
            return [
                "type": "object",
                "properties": props,
                "required": properties.map(\.name),
                "additionalProperties": false
            ]
        case .string(let choices):
            if let choices, !choices.isEmpty { return ["type": "string", "enum": choices] }
            return ["type": "string"]
        case .integer: return ["type": "integer"]
        case .number: return ["type": "number"]
        case .array(let item): return ["type": "array", "items": item.jsonSchema()]
        }
    }
}

struct AISchemaProperty {
    let name: String
    let description: String?
    let schema: AISchema
    var isOptional = false
}

/// What a feature asks for.
struct AIStructuredRequest {
    /// Instructions (system prompt).
    let instructions: String
    let prompt: String
    let schema: AISchema
    /// Short, simple task: use the engine's quick model and low effort.
    var quick = true
}

// MARK: - Errors

enum AIError: LocalizedError {
    case disabled
    case unavailable(String)
    case missingKey(AIEngineKind)
    case badKey(AIEngineKind)
    case quota(AIEngineKind)
    case refused
    case http(Int, String?)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .disabled: return String(localized: "AI features are turned off.")
        case .unavailable(let why): return why
        case .missingKey(let kind): return String(localized: "Add your \(kind.label) API key in Settings → AI.")
        case .badKey(let kind): return String(localized: "\(kind.label) didn't accept the API key.")
        case .quota(let kind): return String(localized: "\(kind.label) says the account is out of credit or over its rate limit.")
        case .refused: return String(localized: "The model declined this request.")
        case .http(let code, let message):
            return message.map { String(localized: "Request failed (\(code)): \($0)") } ?? String(localized: "Request failed (\(code)).")
        case .badResponse(let why): return String(localized: "The model's answer couldn't be read: \(why)")
        }
    }
}

// MARK: - Entry point

enum AIService {
    /// JSON matching `request.schema`, from the engine picked in settings
    /// (falling back to Apple Intelligence when allowed).
    static func generateJSON(_ request: AIStructuredRequest) async throws -> Data {
        let snapshot = await MainActor.run { () -> (Bool, AIEngineKind, String, String, Bool) in
            let s = AISettings.shared
            return (s.isEnabled, s.engine, s.apiKey(for: s.engine), s.model(for: s.engine, quick: request.quick), s.fallbackToApple)
        }
        let (enabled, kind, key, model, fallback) = snapshot
        guard enabled else { throw AIError.disabled }

        do {
            return try await generate(request, kind: kind, key: key, model: model)
        } catch {
            guard kind != .apple, fallback, AppleEngine.availability == nil else { throw error }
            logWarn("[AI] \(kind.shortLabel) failed (\(error.localizedDescription)); using Apple Intelligence")
            return try await AppleEngine().generateJSON(request)
        }
    }

    /// One request on a specific engine (also used by Settings → Test).
    static func generate(_ request: AIStructuredRequest, kind: AIEngineKind, key: String, model: String) async throws -> Data {
        switch kind {
        case .apple: return try await AppleEngine().generateJSON(request)
        case .anthropic: return try await AnthropicEngine(key: key, model: model).generateJSON(request)
        case .openAI: return try await OpenAIEngine(key: key, model: model).generateJSON(request)
        }
    }

    /// Models the account can use, newest first.
    static func listModels(kind: AIEngineKind, key: String) async throws -> [AIModelInfo] {
        switch kind {
        case .apple: return []
        case .anthropic: return try await AnthropicEngine(key: key, model: "").listModels()
        case .openAI: return try await OpenAIEngine(key: key, model: "").listModels()
        }
    }
}

// MARK: - Chat with tools

/// A function the model may call. `run` gets the arguments as JSON and returns
/// text (usually JSON) for the model to read.
struct AITool: @unchecked Sendable {
    let name: String
    let description: String
    /// Must be an `.object`.
    let parameters: AISchema
    let run: @Sendable (Data) async -> String
}

struct AIChatTurn: Equatable {
    enum Role: String { case user, assistant }
    let role: Role
    let text: String
}

extension AIService {
    /// The model's reply to the last user turn in `history`, after any tool calls.
    static func chat(instructions: String, history: [AIChatTurn], tools: [AITool]) async throws -> String {
        let snapshot = await MainActor.run { () -> (Bool, AIEngineKind, String, String, Bool) in
            let s = AISettings.shared
            return (s.isEnabled, s.engine, s.apiKey(for: s.engine), s.model(for: s.engine, quick: false), s.fallbackToApple)
        }
        let (enabled, kind, key, model, fallback) = snapshot
        guard enabled else { throw AIError.disabled }
        do {
            switch kind {
            case .apple: return try await AppleEngine().chat(instructions: instructions, history: history, tools: tools)
            case .anthropic: return try await AnthropicEngine(key: key, model: model).chat(instructions: instructions, history: history, tools: tools)
            case .openAI: return try await OpenAIEngine(key: key, model: model).chat(instructions: instructions, history: history, tools: tools)
            }
        } catch {
            guard kind != .apple, fallback, AppleEngine.availability == nil else { throw error }
            logWarn("[AI] \(kind.shortLabel) chat failed (\(error.localizedDescription)); using Apple Intelligence")
            return try await AppleEngine().chat(instructions: instructions, history: history, tools: tools)
        }
    }

    /// Most tool rounds before the model must answer.
    static let maxToolRounds = 6
}

struct AIModelInfo: Identifiable, Hashable {
    let id: String
    let name: String
}

// MARK: - HTTP

private enum AIHTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90
        return URLSession(configuration: config)
    }()

    static func send(_ request: URLRequest, kind: AIEngineKind) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        logInfo("[AI] \(kind.shortLabel) \(request.url?.path ?? "") → \(status)")
        switch status {
        case 200..<300: return data
        case 401, 403: throw AIError.badKey(kind)
        case 402, 429: throw AIError.quota(kind)
        default: throw AIError.http(status, errorMessage(in: data))
        }
    }

    /// `{"error": {"message": ...}}`, shared by both providers.
    static func errorMessage(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }
}

// MARK: - Anthropic

private struct AnthropicEngine {
    let key: String
    let model: String

    private static let base = URL(string: "https://api.anthropic.com/v1")!

    private func request(_ path: String, method: String, body: [String: Any]? = nil) throws -> URLRequest {
        guard !key.isEmpty else { throw AIError.missingKey(.anthropic) }
        var request = URLRequest(url: Self.base.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return request
    }

    func generateJSON(_ req: AIStructuredRequest) async throws -> Data {
        // Thinking stays at its default (adaptive); effort sets how much.
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8000,
            "system": req.instructions,
            "messages": [["role": "user", "content": req.prompt]],
            "output_config": [
                "effort": req.quick ? "low" : "medium",
                "format": ["type": "json_schema", "schema": req.schema.jsonSchema()]
            ]
        ]
        let data = try await AIHTTP.send(try request("messages", method: "POST", body: body), kind: .anthropic)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badResponse("not JSON")
        }
        if (json["stop_reason"] as? String) == "refusal" { throw AIError.refused }
        if (json["stop_reason"] as? String) == "max_tokens" { throw AIError.badResponse("answer was cut off") }
        let blocks = json["content"] as? [[String: Any]] ?? []
        guard let text = blocks.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
              let out = text.data(using: .utf8) else { throw AIError.badResponse("no text") }
        return out
    }

    func chat(instructions: String, history: [AIChatTurn], tools: [AITool]) async throws -> String {
        var messages: [[String: Any]] = history.map { ["role": $0.role.rawValue, "content": $0.text] }
        let toolDefs: [[String: Any]] = tools.map {
            ["name": $0.name, "description": $0.description, "input_schema": $0.parameters.jsonSchema(), "strict": true]
        }
        for _ in 0...AIService.maxToolRounds {
            let body: [String: Any] = [
                "model": model,
                "max_tokens": 16000,
                "system": instructions,
                "messages": messages,
                "tools": toolDefs,
                "output_config": ["effort": "medium"]
            ]
            let data = try await AIHTTP.send(try request("messages", method: "POST", body: body), kind: .anthropic)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.badResponse("not JSON") }
            let stop = json["stop_reason"] as? String
            if stop == "refusal" { throw AIError.refused }
            let content = json["content"] as? [[String: Any]] ?? []
            let calls = content.filter { ($0["type"] as? String) == "tool_use" }
            guard stop == "tool_use", !calls.isEmpty else {
                let text = content.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }.joined()
                guard !text.isEmpty else { throw AIError.badResponse("no text") }
                return text
            }
            // The assistant turn goes back unchanged (thinking blocks included).
            messages.append(["role": "assistant", "content": content])
            var results: [[String: Any]] = []
            for call in calls {
                let id = call["id"] as? String ?? ""
                let name = call["name"] as? String ?? ""
                let input = (try? JSONSerialization.data(withJSONObject: call["input"] ?? [:])) ?? Data("{}".utf8)
                if let tool = tools.first(where: { $0.name == name }) {
                    results.append(["type": "tool_result", "tool_use_id": id, "content": await tool.run(input)])
                } else {
                    results.append(["type": "tool_result", "tool_use_id": id, "content": "Unknown tool", "is_error": true])
                }
            }
            messages.append(["role": "user", "content": results])
        }
        throw AIError.badResponse("too many tool calls")
    }

    func listModels() async throws -> [AIModelInfo] {
        var request = try request("models", method: "GET")
        request.url = URL(string: "https://api.anthropic.com/v1/models?limit=100")
        let data = try await AIHTTP.send(request, kind: .anthropic)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let list = json?["data"] as? [[String: Any]] ?? []
        return list.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            return AIModelInfo(id: id, name: item["display_name"] as? String ?? id)
        }
    }
}

// MARK: - OpenAI

private struct OpenAIEngine {
    let key: String
    let model: String

    private static let base = URL(string: "https://api.openai.com/v1")!

    private func request(_ path: String, method: String, body: [String: Any]? = nil) throws -> URLRequest {
        guard !key.isEmpty else { throw AIError.missingKey(.openAI) }
        var request = URLRequest(url: Self.base.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return request
    }

    func generateJSON(_ req: AIStructuredRequest) async throws -> Data {
        guard !model.isEmpty else { throw AIError.unavailable(String(localized: "Pick an OpenAI model in Settings → AI.")) }
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": req.instructions],
                ["role": "user", "content": req.prompt]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "result", "strict": true, "schema": req.schema.jsonSchema()]
            ]
        ]
        let data = try await AIHTTP.send(try request("chat/completions", method: "POST", body: body), kind: .openAI)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (json["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else { throw AIError.badResponse("no choices") }
        if let refusal = message["refusal"] as? String, !refusal.isEmpty { throw AIError.refused }
        guard let text = message["content"] as? String, let out = text.data(using: .utf8) else {
            throw AIError.badResponse("no content")
        }
        return out
    }

    /// Chat with tools over the Responses API (Chat Completions refuses tools
    /// with reasoning on newer models). Later rounds chain with `previous_response_id`.
    func chat(instructions: String, history: [AIChatTurn], tools: [AITool]) async throws -> String {
        guard !model.isEmpty else { throw AIError.unavailable(String(localized: "Pick an OpenAI model in Settings → AI.")) }
        let toolDefs: [[String: Any]] = tools.map {
            ["type": "function", "name": $0.name, "description": $0.description, "parameters": $0.parameters.jsonSchema(), "strict": true]
        }
        var input: [[String: Any]] = history.map { ["role": $0.role.rawValue, "content": $0.text] }
        var previousId: String?
        for _ in 0...AIService.maxToolRounds {
            var body: [String: Any] = ["model": model, "instructions": instructions, "input": input, "tools": toolDefs]
            if let previousId { body["previous_response_id"] = previousId }
            let data = try await AIHTTP.send(try request("responses", method: "POST", body: body), kind: .openAI)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.badResponse("not JSON") }
            let output = json["output"] as? [[String: Any]] ?? []
            let calls = output.filter { ($0["type"] as? String) == "function_call" }
            guard !calls.isEmpty else {
                var text = ""
                for item in output where (item["type"] as? String) == "message" {
                    for part in item["content"] as? [[String: Any]] ?? [] {
                        if (part["type"] as? String) == "refusal" { throw AIError.refused }
                        if (part["type"] as? String) == "output_text", let t = part["text"] as? String { text += t }
                    }
                }
                guard !text.isEmpty else { throw AIError.badResponse("no text") }
                return text
            }
            previousId = json["id"] as? String
            input = []
            for call in calls {
                let callId = call["call_id"] as? String ?? ""
                let name = call["name"] as? String ?? ""
                let args = Data(((call["arguments"] as? String) ?? "{}").utf8)
                let result = await tools.first(where: { $0.name == name })?.run(args) ?? "Unknown tool"
                input.append(["type": "function_call_output", "call_id": callId, "output": result])
            }
        }
        throw AIError.badResponse("too many tool calls")
    }

    /// Chat models only; embeddings, audio, image and moderation models are left out.
    func listModels() async throws -> [AIModelInfo] {
        let data = try await AIHTTP.send(try request("models", method: "GET"), kind: .openAI)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let list = json?["data"] as? [[String: Any]] ?? []
        let skip = ["embedding", "audio", "realtime", "tts", "whisper", "transcribe", "image", "dall-e", "moderation", "search", "davinci", "babbage", "instruct"]
        return list
            .compactMap { item -> (String, Double)? in
                guard let id = item["id"] as? String else { return nil }
                let lower = id.lowercased()
                guard lower.hasPrefix("gpt") || lower.hasPrefix("o"), !skip.contains(where: { lower.contains($0) }) else { return nil }
                return (id, (item["created"] as? Double) ?? 0)
            }
            .sorted { $0.1 > $1.1 }
            .map { AIModelInfo(id: $0.0, name: $0.0) }
    }
}

// MARK: - Apple Intelligence

struct AppleEngine {
    /// nil when the on-device model can be used, else why not.
    static var availability: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return String(localized: "This Mac can't run Apple Intelligence.")
                case .appleIntelligenceNotEnabled: return String(localized: "Turn on Apple Intelligence in System Settings.")
                case .modelNotReady: return String(localized: "Apple Intelligence is still getting ready. Try again later.")
                @unknown default: return String(localized: "Apple Intelligence isn't available.")
                }
            }
        }
        #endif
        return String(localized: "Apple Intelligence needs macOS 26 or later.")
    }

    func generateJSON(_ req: AIStructuredRequest) async throws -> Data {
        if let why = Self.availability { throw AIError.unavailable(why) }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let root = Self.dynamicSchema(req.schema, name: "Result")
            let schema = try GenerationSchema(root: root, dependencies: [])
            let session = LanguageModelSession(instructions: req.instructions)
            let response = try await session.respond(to: req.prompt, schema: schema)
            guard let data = response.content.jsonString.data(using: .utf8) else {
                throw AIError.badResponse("no text")
            }
            return data
        }
        #endif
        throw AIError.unavailable(String(localized: "Apple Intelligence needs macOS 26 or later."))
    }

    func chat(instructions: String, history: [AIChatTurn], tools: [AITool]) async throws -> String {
        if let why = Self.availability { throw AIError.unavailable(why) }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let appleTools: [any Tool] = try tools.map { tool in
                AppleDynamicTool(
                    name: tool.name,
                    description: tool.description,
                    parameters: try GenerationSchema(root: Self.dynamicSchema(tool.parameters, name: tool.name), dependencies: []),
                    run: tool.run
                )
            }
            let session = LanguageModelSession(tools: appleTools, instructions: instructions)
            // Earlier turns go in as text: the on-device context is small, so keep the last few.
            let earlier = history.dropLast().suffix(6)
                .map { "\($0.role == .user ? "Viewer" : "You"): \($0.text)" }
                .joined(separator: "\n")
            let last = history.last?.text ?? ""
            let prompt = earlier.isEmpty ? last : "Conversation so far:\n\(earlier)\n\nViewer: \(last)"
            let response = try await session.respond(to: prompt)
            return response.content
        }
        #endif
        throw AIError.unavailable(String(localized: "Apple Intelligence needs macOS 26 or later."))
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    static func dynamicSchema(_ schema: AISchema, name: String) -> DynamicGenerationSchema {
        switch schema {
        case .object(let objectName, let properties):
            return DynamicGenerationSchema(
                name: objectName,
                properties: properties.map { property in
                    DynamicGenerationSchema.Property(
                        name: property.name,
                        description: property.description,
                        schema: dynamicSchema(property.schema, name: "\(objectName)_\(property.name)"),
                        isOptional: property.isOptional
                    )
                }
            )
        case .string(let choices):
            if let choices, !choices.isEmpty { return DynamicGenerationSchema(name: name, anyOf: choices) }
            return DynamicGenerationSchema(type: String.self)
        case .integer: return DynamicGenerationSchema(type: Int.self)
        case .number: return DynamicGenerationSchema(type: Double.self)
        case .array(let item): return DynamicGenerationSchema(arrayOf: dynamicSchema(item, name: "\(name)_item"))
        }
    }
    #endif
}


#if canImport(FoundationModels)
/// A FoundationModels tool whose arguments are described at runtime.
@available(macOS 26.0, *)
private struct AppleDynamicTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let run: @Sendable (Data) async -> String

    func call(arguments: GeneratedContent) async throws -> String {
        await run(Data(arguments.jsonString.utf8))
    }
}
#endif
