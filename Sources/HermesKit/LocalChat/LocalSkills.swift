import Foundation

// Local agent abilities, phase 2: prompt-only skills (spec section 4.3). A skill is a name, a short description and a
// body of instructions. Typing `/name` in a local chat uses that skill for that one message. Skills are text: they run
// no code and reach no network.

/// One prompt-only skill.
public struct LocalSkill: Sendable, Equatable, Identifiable {
    /// What follows the `/`: lowercase letters, digits and dashes.
    public let name: String
    /// The title the completion list shows.
    public let title: String
    /// One line on what it does.
    public let summary: String
    /// The instructions the model gets for that message.
    public let body: String

    public var id: String { name }

    /// Characters of a skill body the instructions take (spec section 3, rule 7).
    public static let bodyLimit = 3000

    public init(name: String, title: String, summary: String, body: String) {
        self.name = name
        self.title = title
        self.summary = summary
        self.body = body
    }
}

extension LocalSkill {
    /// The five built-in skills (names approved by Janet, 2026-11-12).
    public static let builtIn: [LocalSkill] = [
        LocalSkill(
            name: "summarize", title: "Summarize",
            summary: "The main points, short",
            body: """
                Summarize the user's text. Give the main points as a few short bullet points, most important first. \
                Keep names, numbers and dates exactly as written. Do not add anything that is not in the text.
                """),
        LocalSkill(
            name: "explain", title: "Explain simply",
            summary: "Plain words, no jargon",
            body: """
                Explain the user's question or text in plain words, as to a smart person new to the subject. Use short \
                sentences and one everyday example. Define any term you cannot avoid.
                """),
        LocalSkill(
            name: "review", title: "Review my writing",
            summary: "Clearer, shorter, correct",
            body: """
                Review the user's writing. First list up to five concrete changes that make it clearer, shorter or \
                more correct, each with the original words and your suggestion. Then give the improved version. Keep \
                the user's voice and meaning.
                """),
        LocalSkill(
            name: "checklist", title: "Make a checklist",
            summary: "Steps you can tick off",
            body: """
                Turn the user's goal or text into a checklist of concrete steps in order. One action per line, starting \
                with a verb, written as "- [ ] step". Group steps under short headings only when there are more than \
                eight.
                """),
        LocalSkill(
            name: "translate", title: "Translate",
            summary: "Into the language you name",
            body: """
                Translate the user's text. If they name a language ("to Spanish: …"), translate into it; otherwise \
                translate into English, or from English into the language they last wrote in. Keep the meaning, tone \
                and formatting. Give only the translation.
                """),
    ]
}

/// A message that starts with `/name`: the skill and the rest of the message.
public struct LocalSkillInvocation: Sendable, Equatable {
    public let skill: LocalSkill
    /// The message without the `/name`, trimmed. May be empty, then the earlier chat is the subject.
    public let message: String

    /// The skill a message calls, or nil. The `/name` must start the message and name a known skill; case doesn't
    /// matter. Anything else is an ordinary message.
    public static func parse(_ text: String, skills: [LocalSkill] = LocalSkill.builtIn) -> LocalSkillInvocation? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let word = trimmed.dropFirst().prefix { !$0.isWhitespace }
        guard let skill = skills.first(where: { $0.name == word.lowercased() }) else { return nil }
        let rest = trimmed.dropFirst(1 + word.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return LocalSkillInvocation(skill: skill, message: rest)
    }

    /// The instructions block for this message: the skill's body, cut to ``LocalSkill/bodyLimit``.
    public var instructionsBlock: String {
        let body =
            skill.body.count > LocalSkill.bodyLimit ? String(skill.body.prefix(LocalSkill.bodyLimit)) : skill.body
        return "For this message, use the skill \"\(skill.title)\":\n" + body
    }

    /// What the model is asked: the message, or the earlier chat when the message is only `/name`.
    public var prompt: String {
        message.isEmpty ? "Apply this to the conversation so far." : message
    }

    /// The local composer's `/` completions: the skills whose name or title starts with `query`, in list order.
    public static func completions(_ query: String, skills: [LocalSkill] = LocalSkill.builtIn) -> [CompletionItem] {
        let query = query.lowercased()
        return skills.filter { query.isEmpty || $0.name.hasPrefix(query) || $0.title.lowercased().hasPrefix(query) }
            .map { CompletionItem(text: "/\($0.name) ", display: "/\($0.name)", meta: $0.summary, kind: "skill") }
    }
}
