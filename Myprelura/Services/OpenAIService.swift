import Foundation

/// Calls OpenAI Chat Completions for Lenny (shopping) or Ann (support). Same API key; different system prompts.
final class OpenAIService {

    static let shared = OpenAIService()

    enum Assistant {
        case lenny  // Shopping, product search
        case ann    // Customer support, orders, refunds
    }

    private let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let model = "gpt-4o-mini"
    private let maxTokens = 120

    /// Lenny system prompt (canonical: docs/lenny-system-prompt.txt)
    /// Prelura only sells preloved fashion. OpenAI decides when to run a product search via [SEARCH: query].
    private static let lennySystemPrompt: String = """
    You are Lenny, the AI assistant for the Prelura fashion marketplace. Prelura sells only preloved fashion: clothing, shoes, and accessories. We do NOT sell electronics, laptops, computers, furniture, vehicles, or other non-fashion items.

    Your role is to help users find fashion items and answer questions about what we offer.

    Rules:
    1. If the user asks for something we do NOT sell (e.g. laptops, phones, furniture, cars): reply briefly and kindly that we don't sell that and we're here for preloved fashion only. Example: "We don't sell laptops — Prelura is all about preloved fashion. Fancy a jacket, dress, or trainers instead?" Do NOT add [SEARCH: ...] in this case.
    2. If the user is asking for clothing, shoes, or accessories we might have: end your reply with exactly one line: [SEARCH: your search query here]. Use a short search phrase (e.g. [SEARCH: navy blazer], [SEARCH: green dress]). The app will show product results only when you include this line.
    3. For greetings or when the request is unclear: respond naturally and ask how you can help. Do NOT add [SEARCH: ...] unless they clearly want a fashion item.
    4. Keep your reply short (under 25 words before the [SEARCH: ...] line if you include one).
    5. Detect colours, categories, and attributes when the user asks for fashion items.
    6. If the user describes colours indirectly (e.g. "lighter than navy"), interpret intelligently (e.g. royal blue, cobalt).
    7. Do not celebrate sad events; respond with understanding.

    Examples:
    User: hi
    AI: Hi, I'm Lenny — welcome to Prelura. How can I help?

    User: I'm looking for a laptop
    AI: We don't sell laptops — we're all about preloved fashion. Looking for a bag, coat, or something else?

    User: green dress
    AI: Here are some green dresses you might like.
    [SEARCH: green dress]

    User: something lighter than navy
    AI: You might like royal blue or cobalt.
    [SEARCH: blue jacket]
    """

    /// Ann: customer support and order issues. Different role from Lenny; same API key.
    private static let annSystemPrompt: String = """
    You are Ann, the customer support assistant for Prelura. Always respond as Ann. Welcome users to Prelura support and ask how you can help.

    Your role is to help with:
    • Order status, delivery, and tracking
    • Refunds and cancellations
    • Item not as described or other order issues
    • General account or marketplace questions

    Rules:
    1. Keep responses short and helpful (under 30 words when possible).
    2. If the user asks about "my orders" or "order status", acknowledge and say they can see their orders below (the app will show an orders list).
    3. For refunds: be empathetic; say refund times vary and they can check the order for status.
    4. For cancellations: explain they can cancel from the order detail if it's still allowed.
    5. If the user greets you, respond as Ann: e.g. "Hi, I'm Ann — welcome to Prelura support. How can I help?"
    6. Do not make up order IDs or details; the app shows their real orders.
    7. If unsure, suggest they check the order detail or describe their issue a bit more.
    """

    /// Returns the API key from Secrets.plist (OPENAI_API_KEY) or from the environment. Paste your key in Prelura-swift/Secrets.plist (create from Secrets.plist.example if needed).
    var apiKey: String {
        if let fromEnv = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !fromEnv.isEmpty {
            return fromEnv
        }
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url) as? [String: Any],
           let key = dict["OPENAI_API_KEY"] as? String, !key.isEmpty {
            return key.trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    var isConfigured: Bool {
        !apiKey.isEmpty
    }

    /// Sends the user message (and optional recent conversation) to OpenAI and returns the assistant reply, or nil on failure. Use assistant to switch between Lenny (shopping) and Ann (support). For Ann, pass orderContext to inject the user's orders (placed vs sold) so Ann can reference them.
    func reply(userMessage: String, conversationHistory: [(user: String, assistant: String)] = [], assistant: Assistant = .lenny, orderContext: String? = nil) async -> String? {
        guard isConfigured else { return nil }

        var systemContent = assistant == .ann ? Self.annSystemPrompt : Self.lennySystemPrompt
        if assistant == .ann, let ctx = orderContext, !ctx.isEmpty {
            systemContent += "\n\n" + ctx
        }
        var messages: [[String: String]] = [
            ["role": "system", "content": systemContent]
        ]
        for (u, a) in conversationHistory {
            messages.append(["role": "user", "content": u])
            messages.append(["role": "assistant", "content": a])
        }
        messages.append(["role": "user", "content": userMessage])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": 0.7
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode != 200 {
                #if DEBUG
                if let str = String(data: data, encoding: .utf8) {
                    print("[OpenAIService] HTTP \(http.statusCode): \(str)")
                }
                #endif
                return nil
            }
            return parseReply(from: data)
        } catch {
            #if DEBUG
            print("[OpenAIService] Error: \(error)")
            #endif
            return nil
        }
    }

    private func parseReply(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
