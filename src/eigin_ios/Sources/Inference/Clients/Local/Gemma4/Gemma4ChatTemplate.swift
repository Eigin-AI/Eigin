import Foundation

/// Minimal Gemma 4 Jinja chat template for text-only conversations.
///
/// The full upstream template from
/// https://huggingface.co/google/gemma-4-E2B-it/blob/main/chat_template.jinja
/// uses macros, namespaces, and filters (``dictsort``, ``.get()``, ``.split()``)
/// that swift-jinja doesn't fully support, so it fails to parse.
///
/// This minimal variant handles the common text-only path:
/// - BOS token via the tokenizer's special token
/// - System turn when the first message has `role == "system"`
/// - User / assistant turns via `<|turn>user` / `<|turn>model`
/// - Generation prompt at the end so the model knows to continue
///
/// Tool calls, multimodal content (image/audio/video), and thinking/reasoning
/// aren't supported yet — add branches here if they're needed.
enum GemmaChatTemplate {
    static let jinja: String = """
    {{- bos_token -}}
    {%- if messages[0]['role'] == 'system' -%}
    <|turn>system
    {{ messages[0]['content'] | trim }}<turn|>
    {%- set loop_messages = messages[1:] -%}
    {%- else -%}
    {%- set loop_messages = messages -%}
    {%- endif -%}
    {%- for message in loop_messages -%}
    {%- if message['role'] == 'user' -%}
    <|turn>user
    {{ message['content'] | trim }}<turn|>
    {%- elif message['role'] == 'assistant' -%}
    <|turn>model
    {{ message['content'] | trim }}<turn|>
    {%- endif -%}
    {%- endfor -%}
    <|turn>model

    """
}
