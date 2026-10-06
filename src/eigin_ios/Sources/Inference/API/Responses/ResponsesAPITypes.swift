import Foundation

// MARK: - Request

/// Request body for `POST /v1/responses` under the Sign in with ChatGPT flow:
/// `store: false` and `stream: true` are required; inference-controlling
/// fields (temperature, top_p, max_output_tokens, …) are omitted per SIWC's
/// preview limitations.
struct ResponsesRequestBody: Encodable {
    let model: String
    /// System-role content. The Responses API rejects `system` messages in
    /// `input`, so all of it lands here.
    var instructions: String?
    let input: [ResponsesInputItem]
    var tools: [ResponsesFunctionTool]?
    let store = false
    let stream = true

    enum CodingKeys: String, CodingKey {
        case model, instructions, input, tools, store, stream
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encodeIfPresent(instructions, forKey: .instructions)
        try container.encode(input, forKey: .input)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encode(store, forKey: .store)
        try container.encode(stream, forKey: .stream)
    }
}

/// One entry of the `input` array: a message, a tool invocation the model
/// asked for, or a tool result.
enum ResponsesInputItem: Encodable {
    case message(role: String, content: [ResponsesContentPart])
    case functionCall(callID: String, name: String, arguments: String)
    case functionCallOutput(callID: String, output: String)

    private enum CodingKeys: String, CodingKey {
        case type, role, content
        case callID = "call_id"
        case name, arguments, output
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .message(let role, let content):
            try container.encode("message", forKey: .type)
            try container.encode(role, forKey: .role)
            try container.encode(content, forKey: .content)
        case .functionCall(let callID, let name, let arguments):
            try container.encode("function_call", forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(name, forKey: .name)
            try container.encode(arguments, forKey: .arguments)
        case .functionCallOutput(let callID, let output):
            try container.encode("function_call_output", forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(output, forKey: .output)
        }
    }
}

/// Typed content part inside a message item. `input_image` is a data URL so
/// attachment bytes never touch a server of ours — they go straight to the API.
enum ResponsesContentPart: Encodable {
    case inputText(String)
    case outputText(String)
    case inputImage(dataURL: String)

    private enum CodingKeys: String, CodingKey {
        case type, text
        case imageDataURL = "image_url"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inputText(let text):
            try container.encode("input_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .outputText(let text):
            try container.encode("output_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .inputImage(let dataURL):
            try container.encode("input_image", forKey: .type)
            try container.encode(dataURL, forKey: .imageDataURL)
        }
    }
}

/// Function tool in the Responses API's flat shape — no wrapper `function`
/// object like chat completions.
struct ResponsesFunctionTool: Encodable {
    let type = "function"
    let name: String
    let description: String
    let parameters: JSONSchema

    init(from definition: ToolDefinition) {
        name = definition.function.name
        description = definition.function.description
        parameters = definition.function.parameters
    }

    enum CodingKeys: String, CodingKey {
        case type, name, description, parameters
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(parameters, forKey: .parameters)
    }
}

// MARK: - Models

/// Response from `GET /v1/models` with a ChatGPT subscription token: a
/// `models` array with slug/visibility. Decoded tolerantly: the standard
/// OpenAI-compatible `data` shape is accepted as a fallback, and entries
/// without `visibility` are treated as listed so a shape change can't blank
/// out the picker.
struct ResponsesModelsResponse: Decodable {
    let data: [DataEntry]?
    let models: [ModelEntry]?

    struct DataEntry: Decodable {
        let id: String
    }

    struct ModelEntry: Decodable {
        let slug: String?
        let id: String?
        let visibility: String?
    }
}

// MARK: - Stream events

/// One decoded SSE `data:` payload. All fields optional: values are read
/// per `type` after decoding. See the Responses API streaming reference.
struct ResponsesStreamEvent: Decodable {
    let type: String?
    let delta: String?
    let item: Item?
    let response: ResponseEnvelope?
    /// Top-level fields of the bare `error` event.
    let code: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case type, delta, item, response, code, message
    }

    struct Item: Decodable {
        let type: String?
        let callID: String?
        let name: String?
        let arguments: String?

        enum CodingKeys: String, CodingKey {
            case type
            case callID = "call_id"
            case name, arguments
        }
    }

    struct ResponseEnvelope: Decodable {
        let error: APIError?
        let incompleteDetails: IncompleteDetails?
        let usage: Usage?

        struct APIError: Decodable {
            let code: String?
            let message: String?
            let param: String?
        }

        struct IncompleteDetails: Decodable {
            let reason: String?
        }

        struct Usage: Decodable {
            let totalTokens: Int?
        }
    }
}
