//
//  AskFlixor.swift
//  FlixorMac
//
//  Ask Flixor: a chat that answers from the user's own data. The model can
//  call tools (TMDB search and details, the Plex library, the watchlist, watch
//  history, Upcoming) and must not state facts about titles without them.
//  Every title a tool returned and the answer names becomes a card.
//

import Foundation
import FlixorKit

/// A title a tool returned, for cards under the answer.
struct AskTitleCard: Identifiable, Hashable, Codable {
    let item: MediaItem
    let posterURL: URL?
    var subtitle: String
    /// The model's short note for this pick ("Start here").
    var note: String?
    /// Position in an ordered list (1, 2, 3…), when order matters.
    var rank: Int?
    var id: String { item.id }

    static func == (a: Self, b: Self) -> Bool { a.item.id == b.item.id && a.note == b.note && a.rank == b.rank && a.subtitle == b.subtitle }
    func hash(into hasher: inout Hasher) { hasher.combine(item.id) }
}

/// A person a tool returned (cast, crew, search), for chips under the answer.
struct AskPersonCard: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let profilePath: String?
    /// "Frank Abagnale Jr.", "Director", "Acting".
    let subtitle: String

    var profileURL: URL? { TMDBImageURL.url(profilePath, size: .w185) }
}

/// A studio, network or film series a tool returned, as a chip under the answer.
struct AskEntityCard: Identifiable, Hashable, Codable {
    enum Kind: String, Codable { case company, network, collection }
    let kind: Kind
    let tmdbId: Int
    let name: String
    let logoPath: String?
    /// For a collection: the first film, whose Details page lists the series.
    var firstPart: MediaItem?

    var id: String { "\(kind.rawValue):\(tmdbId)" }
    var logoURL: URL? { TMDBImageURL.url(logoPath, size: .w185) }
    var label: String {
        switch kind {
        case .company: return String(localized: "Studio")
        case .network: return String(localized: "Network")
        case .collection: return String(localized: "Series")
        }
    }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One lookup while answering: "Searched TMDB for “Dune”".
struct AskStep: Identifiable, Hashable, Codable {
    var id = UUID()
    var label: String
    var done: Bool
}

struct AskMessage: Identifiable, Equatable, Codable {
    var id = UUID()
    let role: AIChatTurn.Role
    var text: String
    var cards: [AskTitleCard] = []
    var people: [AskPersonCard] = []
    var entities: [AskEntityCard] = []
    /// "Used: your Plex library · TMDB"
    var used: [String] = []
    var steps: [AskStep] = []
    /// Questions the viewer might ask next.
    var followUps: [String] = []
    /// The title the question was about ("Looking at"), for user turns.
    var contextTitle: String?
    /// An error in place of an answer.
    var isError = false
    /// The answer was stopped part way.
    var wasStopped = false
}

extension AIChatTurn.Role: Codable {}

/// A saved conversation.
struct AskConversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var updatedAt: Date
    var messages: [AskMessage]
}

/// The title on screen in each tab, so questions can be about it by default.
@MainActor
final class AskContext: ObservableObject {
    static let shared = AskContext()
    private struct Entry: Equatable { let token: UUID; let item: MediaItem; static func == (a: Entry, b: Entry) -> Bool { a.token == b.token } }
    @Published private var stacks: [NavItem: [Entry]] = [:]

    func push(_ item: MediaItem, tab: NavItem) -> UUID {
        let token = UUID()
        stacks[tab, default: []].append(Entry(token: token, item: item))
        return token
    }

    func remove(_ token: UUID) {
        for tab in stacks.keys { stacks[tab]?.removeAll { $0.token == token } }
    }

    func current(for tab: NavItem) -> MediaItem? { stacks[tab]?.last?.item }
}

@MainActor
final class AskFlixorModel: ObservableObject {
    @Published private(set) var messages: [AskMessage] = []
    @Published private(set) var isSending = false
    /// The answer being written, and the lookups so far.
    @Published private(set) var liveText = ""
    @Published private(set) var liveSteps: [AskStep] = []
    @Published private(set) var conversations: [AskConversation] = []
    /// Answers that arrived while the window was minimised or closed.
    @Published private(set) var unread = 0
    var isVisible = true { didSet { if isVisible { unread = 0 } } }

    private var currentId = UUID()
    private var task: Task<Void, Never>?
    private var profileKey = ""

    static let suggestions: [(String, String)] = [
        (String(localized: "Something light for tonight"), String(localized: "About 90 minutes")),
        (String(localized: "What's new from my shows?"), String(localized: "Upcoming episodes")),
        (String(localized: "Pick something from my watchlist"), String(localized: "Your saved titles")),
        (String(localized: "Best A24 films I haven't seen"), String(localized: "Studios work too")),
    ]

    init() { loadForProfile() }

    // MARK: Conversations

    func newConversation() {
        stop()
        saveCurrent()
        messages = []
        currentId = UUID()
    }

    func open(_ conversation: AskConversation) {
        stop()
        saveCurrent()
        currentId = conversation.id
        messages = conversation.messages
    }

    func delete(_ conversation: AskConversation) {
        conversations.removeAll { $0.id == conversation.id }
        if conversation.id == currentId { messages = []; currentId = UUID() }
        persist()
    }

    /// Re-reads saved conversations after a profile switch.
    func loadForProfile() {
        let key = UserDefaults.standard.profileKey("askFlixorHistory")
        guard key != profileKey else { return }
        profileKey = key
        conversations = (try? JSONDecoder().decode([AskConversation].self, from: Data(contentsOf: Self.fileURL(key)))) ?? []
        messages = []
        currentId = UUID()
    }

    private func saveCurrent() {
        guard let firstQuestion = messages.first(where: { $0.role == .user }) else { return }
        let conversation = AskConversation(id: currentId, title: String(firstQuestion.text.prefix(80)), updatedAt: Date(), messages: messages)
        conversations.removeAll { $0.id == currentId }
        conversations.insert(conversation, at: 0)
        conversations = Array(conversations.prefix(40))
        persist()
    }

    private func persist() {
        let url = Self.fileURL(profileKey)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(conversations).write(to: url, options: .atomic)
    }

    private static func fileURL(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Flixor/AskFlixor/\(String(safe)).json")
    }

    // MARK: Asking

    func send(_ text: String, context: MediaItem?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        var question = AskMessage(role: .user, text: trimmed)
        if let context { question.contextTitle = context.year.map { "\(context.title) (\(String($0)))" } ?? context.title }
        messages.append(question)
        run(context: context)
    }

    /// Asks the last question again.
    func retry() {
        guard !isSending, let last = messages.lastIndex(where: { $0.role == .user }) else { return }
        messages.removeSubrange((last + 1)...)
        run(context: nil)
    }

    func stop() {
        task?.cancel()
    }

    private func run(context: MediaItem?) {
        isSending = true
        liveText = ""
        liveSteps = []
        var history = messages.filter { !$0.isError }.suffix(12).map { AIChatTurn(role: $0.role, text: $0.text) }
        if let last = messages.last, last.role == .user, let title = last.contextTitle {
            let ref = context.map { " (ref \($0.id))" } ?? ""
            history[history.count - 1] = AIChatTurn(role: .user, text: "[The viewer is looking at \(title)\(ref).] \(last.text)")
        }
        let turns = Array(history)
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let toolbox = AskToolbox { [weak self] step in
                await MainActor.run {
                    guard let self else { return }
                    if let i = self.liveSteps.firstIndex(where: { $0.id == step.id }) { self.liveSteps[i] = step } else { self.liveSteps.append(step) }
                }
            }
            defer {
                self.isSending = false
                self.liveText = ""
                self.task = nil
                self.saveCurrent()
            }
            do {
                let reply = try await AIService.chat(instructions: Self.instructions(), history: turns, tools: toolbox.tools()) { [weak self] text in
                    await MainActor.run { self?.liveText = AskReply.visibleText(text) }
                }
                let parsed = AskReply(reply)
                var cards = await toolbox.cards(for: parsed.picks, ordered: parsed.ordered)
                if cards.isEmpty { cards = await toolbox.cards(mentionedIn: parsed.text) }
                let people = await toolbox.people(mentionedIn: parsed.text)
                let entities = await toolbox.entities(mentionedIn: parsed.text)
                let used = await toolbox.usedSources()
                var answer = AskMessage(role: .assistant, text: parsed.text, cards: cards, people: people, entities: entities, used: used)
                answer.steps = self.liveSteps.map { var s = $0; s.done = true; return s }
                answer.followUps = parsed.followUps
                self.messages.append(answer)
                if !self.isVisible { self.unread += 1 }
            } catch is CancellationError {
                var stopped = AskMessage(role: .assistant, text: self.liveText.isEmpty ? String(localized: "Stopped.") : self.liveText)
                stopped.wasStopped = true
                stopped.steps = self.liveSteps
                self.messages.append(stopped)
            } catch {
                var failed = AskMessage(role: .assistant, text: error.localizedDescription)
                failed.isError = true
                self.messages.append(failed)
            }
        }
    }

    private static func instructions() -> String {
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .none)
        return """
        You are the assistant inside Flixor, a movie and TV app. Today is \(today). \
        Answer the viewer's questions about movies, shows and their own library. \
        Use the tools to look things up: never state a title's year, runtime, cast, rating or availability unless a tool returned it. \
        When recommending, prefer titles from the viewer's watchlist, library and history, and skip ones they have watched. \
        For questions about actors, directors or cast, use search_people, person_credits and title_details. \
        For studios (A24, Pixar), TV networks (HBO, Netflix) or film series (Dune, Harry Potter), use \
        search_studios_networks with titles_from, or search_collections. \
        When the viewer is looking at a title, questions like "who's in it" are about that title. \
        Write exact titles and people's names as the tools returned them. \
        Keep the answer to one to three plain sentences and do NOT list the titles in the text: the app shows them as cards. \
        Don't use markdown headings, tables or bullet lists.

        After the answer, on new lines, add:
        PICKS: (write "PICKS (ordered):" when order matters, like a series or a ranking)
        one line per title you recommend or list, best or first first, at most 8, as: ref | note
        where ref is exactly a ref a tool returned (like tmdb:movie:438631 or plex:1234) and note is optional, at most 8 words.
        FOLLOWUPS:
        two or three short questions the viewer might ask next, one per line.
        """
    }
}

/// A reply split into its text, picks and follow-ups.
struct AskReply {
    let text: String
    let picks: [(ref: String, note: String?)]
    let ordered: Bool
    let followUps: [String]

    init(_ raw: String) {
        let lines = raw.components(separatedBy: "\n")
        var textLines: [String] = []
        var picks: [(String, String?)] = []
        var followUps: [String] = []
        var ordered = false
        var section = 0 // 0 text, 1 picks, 2 follow-ups
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()
            if upper.hasPrefix("PICKS") { section = 1; ordered = upper.contains("ORDERED"); continue }
            if upper.hasPrefix("FOLLOWUPS") || upper.hasPrefix("FOLLOW-UPS") { section = 2; continue }
            switch section {
            case 0: textLines.append(line)
            case 1:
                let cleaned = trimmed.drop { "-•*0123456789. ".contains($0) }
                guard !cleaned.isEmpty else { continue }
                let parts = cleaned.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                let ref = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "`"))
                guard ref.contains(":") else { continue }
                picks.append((ref, parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil))
            default:
                let cleaned = String(trimmed.drop { "-•*0123456789. ".contains($0) })
                if !cleaned.isEmpty { followUps.append(cleaned) }
            }
        }
        text = textLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        self.picks = picks
        self.ordered = ordered
        self.followUps = Array(followUps.prefix(3))
    }

    /// The text part of a reply still being written (hides the trailer, even half-typed).
    static func visibleText(_ raw: String) -> String {
        var text = raw
        for marker in ["\nPICKS", "\nFOLLOWUPS", "PICKS (", "PICKS:"] {
            if let range = text.range(of: marker) { text = String(text[..<range.lowerBound]) }
        }
        // A trailer marker cut off mid-word at the very end.
        for partial in ["\nP", "\nPI", "\nPIC", "\nPICK", "\nF", "\nFO", "\nFOL"] where text.hasSuffix(partial) {
            text = String(text.dropLast(partial.count))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Tools

/// Tools for one reply; remembers the titles they returned.
actor AskToolbox {
    private var found: [String: AskTitleCard] = [:]
    private var order: [String] = []
    private var foundPeople: [Int: AskPersonCard] = [:]
    private var peopleOrder: [Int] = []
    private var foundEntities: [String: AskEntityCard] = [:]
    private var entityOrder: [String] = []
    /// Studios and networks titles_from was used on: the right one among same-named entries.
    private var usedEntities: Set<String> = []
    /// Plex quality by title ref, from title_details ("" = owned, quality unknown).
    private var ownedQuality: [String: String] = [:]
    private var notOwned: Set<String> = []
    private var used: [String] = []
    private let onStep: @Sendable (AskStep) async -> Void

    init(onStep: @escaping @Sendable (AskStep) async -> Void = { _ in }) {
        self.onStep = onStep
    }

    /// The tools, each reporting a step while it runs.
    nonisolated func tools() -> [AITool] {
        rawTools().map { tool in
            let onStep = self.onStep
            return AITool(name: tool.name, description: tool.description, parameters: tool.parameters) { data in
                let (running, done) = Self.stepLabels(tool.name, Self.args(data))
                var step = AskStep(label: running, done: false)
                await onStep(step)
                let result = await tool.run(data)
                step.label = done
                step.done = true
                await onStep(step)
                return result
            }
        }
    }

    private static func stepLabels(_ name: String, _ args: [String: Any]) -> (String, String) {
        let q = (args["query"] as? String).map { "“\($0)”" } ?? ""
        switch name {
        case "search_titles": return (String(localized: "Searching TMDB for \(q)…"), String(localized: "Searched TMDB for \(q)"))
        case "title_details": return (String(localized: "Looking up details…"), String(localized: "Looked up details"))
        case "search_people": return (String(localized: "Finding \(q)…"), String(localized: "Found \(q)"))
        case "person_credits": return (String(localized: "Listing their films…"), String(localized: "Listed their films"))
        case "search_studios_networks": return (String(localized: "Finding \(q)…"), String(localized: "Found studio \(q)"))
        case "titles_from": return (String(localized: "Listing their titles…"), String(localized: "Listed their titles"))
        case "search_collections": return (String(localized: "Finding the \(q) series…"), String(localized: "Listed the \(q) series"))
        case "search_my_library": return (String(localized: "Checking your Plex library…"), String(localized: "Checked your Plex library"))
        case "my_watchlist": return (String(localized: "Reading your watchlist…"), String(localized: "Read your watchlist"))
        case "my_recent_history": return (String(localized: "Reading your watch history…"), String(localized: "Read your watch history"))
        case "upcoming_episodes": return (String(localized: "Checking upcoming episodes…"), String(localized: "Checked upcoming episodes"))
        default: return (String(localized: "Looking it up…"), String(localized: "Looked it up"))
        }
    }

    private nonisolated func rawTools() -> [AITool] {
        [
            AITool(
                name: "search_titles",
                description: "Search TMDB for movies and TV shows by title, person or topic. Returns refs to use with title_details.",
                parameters: .object(name: "SearchTitles", properties: [
                    AISchemaProperty(name: "query", description: "What to search for", schema: .string()),
                    AISchemaProperty(name: "type", description: "movie, tv or any", schema: .string(choices: ["movie", "tv", "any"]))
                ]),
                run: { [self] data in await self.searchTitles(data) }
            ),
            AITool(
                name: "title_details",
                description: "Details of one title by ref: runtime, genres, overview, director, main cast, and whether it's in the viewer's Plex library.",
                parameters: .object(name: "TitleDetails", properties: [
                    AISchemaProperty(name: "ref", description: "A ref from another tool, like tmdb:movie:603", schema: .string())
                ]),
                run: { [self] data in await self.titleDetails(data) }
            ),
            AITool(
                name: "search_people",
                description: "Find actors, directors and other people by name. Returns person refs for person_credits.",
                parameters: .object(name: "SearchPeople", properties: [
                    AISchemaProperty(name: "query", description: "The person's name", schema: .string())
                ]),
                run: { [self] data in await self.searchPeople(data) }
            ),
            AITool(
                name: "person_credits",
                description: "A person's best-known movies and shows, by person ref.",
                parameters: .object(name: "PersonCredits", properties: [
                    AISchemaProperty(name: "person_ref", description: "A ref like tmdb:person:6193", schema: .string())
                ]),
                run: { [self] data in await self.personCredits(data) }
            ),
            AITool(
                name: "search_studios_networks",
                description: "Find film studios and production companies (A24, Pixar, Marvel Studios) or TV networks and streamers (HBO, Netflix, Apple TV+). Returns refs for titles_from.",
                parameters: .object(name: "SearchStudios", properties: [
                    AISchemaProperty(name: "query", description: "Studio or network name", schema: .string())
                ]),
                run: { [self] data in await self.searchStudios(data) }
            ),
            AITool(
                name: "titles_from",
                description: "Movies or shows from a studio or network ref, most popular or newest first.",
                parameters: .object(name: "TitlesFrom", properties: [
                    AISchemaProperty(name: "ref", description: "A ref like tmdb:company:41077 or tmdb:network:49", schema: .string()),
                    AISchemaProperty(name: "type", description: "movie or tv (networks only have tv)", schema: .string(choices: ["movie", "tv"])),
                    AISchemaProperty(name: "sort", description: "popular or newest", schema: .string(choices: ["popular", "newest"]))
                ]),
                run: { [self] data in await self.titlesFrom(data) }
            ),
            AITool(
                name: "search_collections",
                description: "Find a film series or franchise (Dune, The Lord of the Rings) and list its films in release order.",
                parameters: .object(name: "SearchCollections", properties: [
                    AISchemaProperty(name: "query", description: "Series name", schema: .string())
                ]),
                run: { [self] data in await self.searchCollections(data) }
            ),
            AITool(
                name: "search_my_library",
                description: "Search the viewer's own Plex library by title. Returns what they own and its video quality.",
                parameters: .object(name: "SearchLibrary", properties: [
                    AISchemaProperty(name: "query", description: "Title to look for", schema: .string())
                ]),
                run: { [self] data in await self.searchLibrary(data) }
            ),
            AITool(
                name: "my_watchlist",
                description: "The viewer's watchlist: titles they saved to watch later.",
                parameters: .object(name: "Watchlist", properties: []),
                run: { [self] _ in await self.watchlist() }
            ),
            AITool(
                name: "my_recent_history",
                description: "What the viewer watched recently, newest first.",
                parameters: .object(name: "History", properties: []),
                run: { [self] _ in await self.history() }
            ),
            AITool(
                name: "upcoming_episodes",
                description: "New episodes of the viewer's shows that they haven't watched, and episodes airing in the next 30 days.",
                parameters: .object(name: "Upcoming", properties: []),
                run: { [self] _ in await self.upcoming() }
            ),
        ]
    }

    // MARK: Results for the panel

    /// Cards for the model's picks, in its order, with its notes.
    func cards(for picks: [(ref: String, note: String?)], ordered: Bool) async -> [AskTitleCard] {
        var seen = Set<String>()
        var list: [AskTitleCard] = []
        for pick in picks.prefix(8) {
            guard var card = found[pick.ref], seen.insert(card.id).inserted else { continue }
            card.note = pick.note
            list.append(card)
        }
        if ordered, list.count > 1 { for i in list.indices { list[i].rank = i + 1 } }
        return await withOwnership(list)
    }

    /// Cards the reply names, each saying whether it's on the viewer's Plex.
    func cards(mentionedIn reply: String) async -> [AskTitleCard] {
        await withOwnership(namedCards(in: reply))
    }

    private func withOwnership(_ cards: [AskTitleCard]) async -> [AskTitleCard] {
        var chosen = cards
        let unknown = chosen.enumerated().filter { _, card in
            card.item.id.hasPrefix("tmdb:") && ownedQuality[card.item.id] == nil && !notOwned.contains(card.item.id)
        }
        let checks = await withTaskGroup(of: (String, String?).self) { group -> [String: String?] in
            for (_, card) in unknown {
                let title = card.item.title
                let year = card.item.year
                let id = card.item.id
                group.addTask { [self] in
                    let hit = await self.plexMatches(title).first { h in
                        (h.title ?? "").caseInsensitiveCompare(title) == .orderedSame
                            && (year == nil || h.year == nil || abs((h.year ?? 0) - (year ?? 0)) <= 1)
                    }
                    return (id, hit.map { $0.quality ?? "" })
                }
            }
            var out: [String: String?] = [:]
            for await (id, quality) in group { out[id] = quality }
            return out
        }
        for (id, quality) in checks {
            if let quality { ownedQuality[id] = quality } else { notOwned.insert(id) }
        }
        for index in chosen.indices {
            let id = chosen[index].item.id
            guard id.hasPrefix("tmdb:"), let quality = ownedQuality[id] else { continue }
            var parts = [chosen[index].subtitle, String(localized: "On your Plex")]
            if !quality.isEmpty { parts.append(quality) }
            chosen[index].subtitle = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return chosen
    }

    func entities(mentionedIn reply: String) -> [AskEntityCard] {
        let text = reply.lowercased()
        let mentioned = entityOrder
            .compactMap { id -> (AskEntityCard, String.Index)? in
                guard let entity = foundEntities[id] else { return nil }
                var name = entity.name.lowercased()
                for suffix in [" collection", " (collection)"] where name.hasSuffix(suffix) { name = String(name.dropLast(suffix.count)) }
                guard name.count >= 2, let range = text.range(of: name) else { return nil }
                return (entity, range.lowerBound)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        // Same name twice (TMDB has several "A24"s): keep the one the answer used, else the first.
        var picked: [String: AskEntityCard] = [:]
        var keys: [String] = []
        for entity in mentioned {
            let key = "\(entity.kind.rawValue)|\(entity.name.lowercased())"
            if let current = picked[key] {
                if !usedEntities.contains(current.id), usedEntities.contains(entity.id) { picked[key] = entity }
            } else {
                picked[key] = entity
                keys.append(key)
            }
        }
        return keys.prefix(6).compactMap { picked[$0] }
    }

    private func rememberEntity(_ entity: AskEntityCard) {
        if foundEntities[entity.id] == nil { entityOrder.append(entity.id) }
        if foundEntities[entity.id]?.firstPart == nil { foundEntities[entity.id] = entity }
    }

    private func namedCards(in reply: String) -> [AskTitleCard] {
        let text = reply.lowercased()
        let mentioned = order.compactMap { id -> (AskTitleCard, String.Index)? in
            guard let card = found[id] else { return nil }
            let title = (card.item.type == "episode" ? (card.item.grandparentTitle ?? card.item.title) : card.item.title).lowercased()
            guard title.count >= 2, let range = text.range(of: title) else { return nil }
            return (card, range.lowerBound)
        }
        // Several cards with one title ("Dune" 1984, 2020, 2021): keep those whose year
        // the reply mentions, else only the first one found.
        let byTitle = Dictionary(grouping: mentioned.map(\.0), by: { $0.item.title.lowercased() })
        let allowed: Set<String> = Set(byTitle.values.flatMap { group -> [String] in
            guard group.count > 1 else { return group.map(\.id) }
            let dated = group.filter { card in card.item.year.map { text.contains(String($0)) } ?? false }
            return (dated.isEmpty ? [group[0]] : dated).map(\.id)
        })
        // Same-title cards follow where their year appears.
        let positioned = mentioned.map { card, index -> (AskTitleCard, String.Index) in
            guard (byTitle[card.item.title.lowercased()]?.count ?? 0) > 1,
                  let year = card.item.year, let at = text.range(of: String(year)) else { return (card, index) }
            return (card, at.lowerBound)
        }
        var seenTitles = Set<String>()
        return positioned
            .sorted { $0.1 < $1.1 }
            .map(\.0)
            .filter { allowed.contains($0.id) }
            .filter { seenTitles.insert("\($0.item.title.lowercased())|\($0.item.year ?? 0)").inserted }
            .prefix(8)
            .map { $0 }
    }

    func people(mentionedIn reply: String) -> [AskPersonCard] {
        let text = reply.lowercased()
        return peopleOrder
            .compactMap { id -> (AskPersonCard, String.Index)? in
                guard let person = foundPeople[id], person.name.count >= 3,
                      let range = text.range(of: person.name.lowercased()) else { return nil }
                return (person, range.lowerBound)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
            .prefix(10)
            .map { $0 }
    }

    func usedSources() -> [String] { used }

    private func rememberPerson(_ person: AskPersonCard) {
        if foundPeople[person.id] == nil { peopleOrder.append(person.id) }
        // Keep the first, most specific subtitle (a character beats a department).
        if foundPeople[person.id] == nil { foundPeople[person.id] = person }
    }

    private func searchPeople(_ data: Data) async -> String {
        note("TMDB")
        let query = Self.args(data)["query"] as? String ?? ""
        let tmdb = await FlixorCore.shared.tmdb
        guard let page = try? await tmdb.searchPeople(query: query) else { return "Search failed." }
        return Self.json(page.results.prefix(5).map { person -> [String: Any] in
            rememberPerson(AskPersonCard(id: person.id, name: person.name, profilePath: person.profilePath,
                                         subtitle: person.knownForDepartment ?? ""))
            return ["person_ref": "tmdb:person:\(person.id)", "name": person.name,
                    "known_for_department": person.knownForDepartment ?? ""]
        })
    }

    private func personCredits(_ data: Data) async -> String {
        note("TMDB")
        let ref = Self.args(data)["person_ref"] as? String ?? ""
        guard let id = ref.split(separator: ":").last.flatMap({ Int($0) }) else { return "Use a tmdb:person:ID ref." }
        let tmdb = await FlixorCore.shared.tmdb
        guard let credits = try? await tmdb.getPersonCredits(id: id) else { return "Not found." }
        let acting = credits.cast
            .filter { $0.mediaType == "movie" || $0.mediaType == "tv" }
            .sorted { ($0.voteCount ?? 0) > ($1.voteCount ?? 0) }
        let directing = credits.crew
            .filter { $0.job == "Director" && ($0.mediaType == "movie" || $0.mediaType == "tv") }
            .sorted { ($0.voteCount ?? 0) > ($1.voteCount ?? 0) }
        func rows(_ list: ArraySlice<TMDBMedia>) -> [[String: Any]] {
            list.map { m in
                let card = tmdbCard(m, type: m.mediaType ?? "movie")
                remember(card)
                return ["ref": card.id, "title": card.item.title, "year": card.item.year ?? 0, "type": m.mediaType ?? ""]
            }
        }
        return Self.json(["acted_in": rows(acting.prefix(15)), "directed": rows(directing.prefix(8))])
    }

    // MARK: Tool bodies

    private func note(_ source: String) {
        if !used.contains(source) { used.append(source) }
    }

    private func remember(_ card: AskTitleCard) {
        if found[card.id] == nil { order.append(card.id) }
        found[card.id] = card
    }

    private static func args(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    private static func clip(_ text: String?, _ limit: Int) -> String {
        guard let text else { return "" }
        return text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }

    private func tmdbCard(_ m: TMDBMedia, type: String) -> AskTitleCard {
        let isMovie = type == "movie"
        let title = m.title ?? m.name ?? ""
        let year = (m.releaseDate ?? m.firstAirDate).flatMap { Int($0.prefix(4)) }
        let item = MediaItem(
            id: "tmdb:\(isMovie ? "movie" : "tv"):\(m.id)", title: title, type: isMovie ? "movie" : "show",
            thumb: TMDBImageURL.url(m.posterPath, size: .w500)?.absoluteString,
            art: TMDBImageURL.url(m.backdropPath, size: .w780)?.absoluteString,
            year: year, rating: m.voteAverage, duration: nil, viewOffset: nil, summary: m.overview,
            grandparentTitle: nil, grandparentThumb: nil, grandparentArt: nil, grandparentRatingKey: nil,
            parentIndex: nil, index: nil, parentRatingKey: nil, parentTitle: nil, leafCount: nil, viewedLeafCount: nil
        )
        return AskTitleCard(
            item: item,
            posterURL: TMDBImageURL.url(m.posterPath, size: .w185),
            subtitle: [year.map(String.init), isMovie ? String(localized: "Movie") : String(localized: "TV show")].compactMap { $0 }.joined(separator: " · ")
        )
    }

    private func searchTitles(_ data: Data) async -> String {
        note("TMDB")
        let a = Self.args(data)
        let query = a["query"] as? String ?? ""
        let type = a["type"] as? String ?? "any"
        let tmdb = await FlixorCore.shared.tmdb
        guard let page = try? await tmdb.searchMulti(query: query) else { return "Search failed." }
        let results = page.results
            .filter { ($0.mediaType == "movie" || $0.mediaType == "tv") && (type == "any" || $0.mediaType == type) }
            .prefix(6)
        return Self.json(results.map { m -> [String: Any] in
            let card = tmdbCard(m, type: m.mediaType ?? "movie")
            remember(card)
            return [
                "ref": card.id, "title": card.item.title, "year": card.item.year ?? 0,
                "type": m.mediaType ?? "", "rating": ((m.voteAverage ?? 0) * 10).rounded() / 10,
                "overview": Self.clip(m.overview, 160)
            ]
        })
    }

    private func titleDetails(_ data: Data) async -> String {
        note("TMDB")
        let ref = Self.args(data)["ref"] as? String ?? ""
        let parts = ref.split(separator: ":")
        guard parts.count == 3, parts[0] == "tmdb", let id = Int(parts[2]) else {
            return "Use a tmdb:movie:ID or tmdb:tv:ID ref from search_titles."
        }
        let tmdb = await FlixorCore.shared.tmdb
        var info: [String: Any] = ["ref": ref]
        var title = ""
        var year: Int?
        if parts[1] == "movie", let d = try? await tmdb.getMovieDetails(id: id) {
            title = d.title ?? ""
            year = d.releaseDate.flatMap { Int($0.prefix(4)) }
            info["title"] = title
            info["year"] = year ?? 0
            info["runtime_minutes"] = d.runtime ?? 0
            info["genres"] = d.genres.map(\.name)
            info["overview"] = Self.clip(d.overview, 400)
            info["rating"] = ((d.voteAverage ?? 0) * 10).rounded() / 10
            if let credits = try? await tmdb.getMovieCredits(id: id) {
                info["director"] = credits.crew.filter { $0.job == "Director" }.map { crew -> [String: Any] in
                    rememberPerson(AskPersonCard(id: crew.id, name: crew.name, profilePath: crew.profilePath, subtitle: String(localized: "Director")))
                    return ["name": crew.name, "person_ref": "tmdb:person:\(crew.id)"]
                }
                info["cast"] = castRows(credits.cast)
            }
            info["studios"] = (d.productionCompanies ?? []).prefix(3).compactMap { c -> [String: Any]? in
                guard let cid = c.id, let name = c.name else { return nil }
                rememberEntity(AskEntityCard(kind: .company, tmdbId: cid, name: name, logoPath: c.logoPath))
                return ["name": name, "ref": "tmdb:company:\(cid)"]
            }
            if let collection = try? await tmdb.getMovieCollectionRef(movieId: id), let name = collection.name {
                rememberEntity(AskEntityCard(kind: .collection, tmdbId: collection.id, name: name, logoPath: collection.posterPath))
                info["part_of_series"] = name
            }
        } else if parts[1] == "tv", let d = try? await tmdb.getTVDetails(id: id) {
            title = d.name ?? ""
            year = d.firstAirDate.flatMap { Int($0.prefix(4)) }
            info["title"] = title
            info["first_aired"] = d.firstAirDate ?? ""
            info["seasons"] = d.numberOfSeasons ?? 0
            info["episode_minutes"] = d.episodeRunTime?.first ?? 0
            info["status"] = d.status ?? ""
            info["genres"] = d.genres.map(\.name)
            info["overview"] = Self.clip(d.overview, 400)
            info["rating"] = ((d.voteAverage ?? 0) * 10).rounded() / 10
            if let next = d.nextEpisodeToAir, let s = next.seasonNumber, let e = next.episodeNumber {
                info["next_episode"] = "S\(s) E\(e) on \(next.airDate ?? "?")"
            }
            if let credits = try? await tmdb.getTVCredits(id: id) {
                info["cast"] = castRows(credits.cast)
            }
            info["networks"] = (d.networks ?? []).prefix(3).compactMap { n -> [String: Any]? in
                guard let nid = n.id, let name = n.name else { return nil }
                rememberEntity(AskEntityCard(kind: .network, tmdbId: nid, name: name, logoPath: n.logoPath))
                return ["name": name, "ref": "tmdb:network:\(nid)"]
            }
        } else {
            return "Not found."
        }
        if let owned = await plexMatches(title).first(where: { year == nil || $0.year == nil || abs(($0.year ?? 0) - (year ?? 0)) <= 1 }) {
            info["in_plex_library"] = true
            if let quality = owned.quality { info["plex_quality"] = quality }
            ownedQuality[ref] = owned.quality ?? ""
        } else {
            info["in_plex_library"] = false
            notOwned.insert(ref)
        }
        return Self.json(info)
    }

    /// Top-billed cast as rows, remembered as chips.
    private func castRows(_ cast: [TMDBCastMember]) -> [[String: Any]] {
        cast.prefix(8).map { member in
            rememberPerson(AskPersonCard(id: member.id, name: member.name, profilePath: member.profilePath,
                                         subtitle: member.character ?? ""))
            return ["name": member.name, "character": member.character ?? "", "person_ref": "tmdb:person:\(member.id)"]
        }
    }

    private struct PlexHit: Decodable {
        struct MediaInfo: Decodable { let videoResolution: String?; let height: Int? }
        let ratingKey: String
        let title: String?
        let year: Int?
        let type: String?
        let thumb: String?
        let Media: [MediaInfo]?
        var quality: String? {
            guard let media = Media?.first else { return nil }
            if let r = media.videoResolution { return r.lowercased() == "4k" ? "4K" : "\(r)p" }
            return media.height.map { $0 >= 2000 ? "4K" : "\($0)p" }
        }
    }

    nonisolated private func plexMatches(_ query: String) async -> [PlexHit] {
        guard !query.isEmpty else { return [] }
        var hits: [PlexHit] = []
        for type in ["1", "2"] {
            let result: [PlexHit]? = try? await APIClient.shared.get(
                "/api/plex/search",
                queryItems: [URLQueryItem(name: "query", value: query), URLQueryItem(name: "type", value: type)]
            )
            hits += result ?? []
        }
        return hits
    }

    private func searchLibrary(_ data: Data) async -> String {
        note(String(localized: "your Plex library"))
        let query = Self.args(data)["query"] as? String ?? ""
        let hits = Array(await plexMatches(query).prefix(8))
        guard !hits.isEmpty else { return "Nothing in the Plex library matches \"\(query)\" (or no Plex library is connected)." }
        let posters = await MainActor.run {
            hits.map { ImageService.shared.plexImageURL(path: $0.thumb, width: 120, height: 180) }
        }
        return Self.json(hits.enumerated().map { index, hit -> [String: Any] in
            let isMovie = hit.type == "movie"
            let item = MediaItem(
                id: "plex:\(hit.ratingKey)", title: hit.title ?? "", type: isMovie ? "movie" : "show", thumb: hit.thumb, art: nil,
                year: hit.year, rating: nil, duration: nil, viewOffset: nil, summary: nil,
                grandparentTitle: nil, grandparentThumb: nil, grandparentArt: nil, grandparentRatingKey: nil,
                parentIndex: nil, index: nil, parentRatingKey: nil, parentTitle: nil, leafCount: nil, viewedLeafCount: nil
            )
            remember(AskTitleCard(
                item: item,
                posterURL: posters[index],
                subtitle: [hit.year.map(String.init), String(localized: "On your Plex"), hit.quality].compactMap { $0 }.joined(separator: " · ")
            ))
            return ["ref": "plex:\(hit.ratingKey)", "title": hit.title ?? "", "year": hit.year ?? 0,
                    "type": isMovie ? "movie" : "tv", "quality": hit.quality ?? "unknown"]
        })
    }

    private func watchlist() async -> String {
        note(String(localized: "your watchlist"))
        var rows: [[String: Any]] = []
        let trakt = await FlixorCore.shared.trakt
        if await trakt.isAuthenticated, let items = try? await trakt.getWatchlist() {
            for entry in items.prefix(30) {
                if let movie = entry.movie, let id = movie.ids.tmdb {
                    rows.append(["ref": "tmdb:movie:\(id)", "title": movie.title, "year": movie.year ?? 0, "type": "movie"])
                    await rememberTMDB(id: id, type: "movie")
                } else if let show = entry.show, let id = show.ids.tmdb {
                    rows.append(["ref": "tmdb:tv:\(id)", "title": show.title, "year": show.year ?? 0, "type": "tv"])
                    await rememberTMDB(id: id, type: "tv")
                }
            }
        }
        for entry in await LocalLibraryStore.shared.watchlist().prefix(30) {
            guard let id = entry.tmdbId, !rows.contains(where: { ($0["ref"] as? String)?.hasSuffix(":\(id)") == true }) else { continue }
            let type = entry.type == "movie" ? "movie" : "tv"
            rows.append(["ref": "tmdb:\(type):\(id)", "title": entry.title, "year": entry.year ?? 0, "type": type])
            await rememberTMDB(id: id, type: type)
        }
        return rows.isEmpty ? "The watchlist is empty." : Self.json(rows)
    }

    /// Card for a TMDB id that came from Trakt or the local store.
    private func rememberTMDB(id: Int, type: String) async {
        let ref = "tmdb:\(type):\(id)"
        guard found[ref] == nil else { return }
        let tmdb = await FlixorCore.shared.tmdb
        if type == "movie", let d = try? await tmdb.getMovieDetails(id: id) {
            let media = TMDBMediaShim(id: d.id, title: d.title, name: nil, posterPath: d.posterPath, backdropPath: d.backdropPath,
                                      date: d.releaseDate, vote: d.voteAverage, overview: d.overview)
            remember(tmdbCard(media.media, type: "movie"))
        } else if type == "tv", let d = try? await tmdb.getTVDetails(id: id) {
            let media = TMDBMediaShim(id: d.id, title: nil, name: d.name, posterPath: d.posterPath, backdropPath: d.backdropPath,
                                      date: d.firstAirDate, vote: d.voteAverage, overview: d.overview)
            remember(tmdbCard(media.media, type: "tv"))
        }
    }

    /// TMDB has no network search; these are matched by name and checked against TMDB.
    private static let knownNetworks: [(names: [String], id: Int)] = [
        (["netflix"], 213), (["hbo"], 49), (["max", "hbo max"], 3186), (["apple tv+", "apple tv", "apple"], 2552),
        (["prime video", "amazon", "amazon prime"], 1024), (["disney+", "disney plus"], 2739), (["hulu"], 453),
        (["amc"], 174), (["fx"], 88), (["bbc one", "bbc"], 4), (["peacock"], 3353), (["paramount+", "paramount plus"], 4330),
        (["showtime"], 67), (["starz"], 318), (["nbc"], 6), (["cbs"], 16), (["abc"], 2), (["fox"], 19),
    ]

    private func searchStudios(_ data: Data) async -> String {
        note("TMDB")
        let query = (Self.args(data)["query"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let lower = query.lowercased()
        let tmdb = await FlixorCore.shared.tmdb
        var rows: [[String: Any]] = []
        for entry in Self.knownNetworks where entry.names.contains(lower) || entry.names.contains(where: { lower.contains($0) && $0.count >= 4 }) {
            guard let network = try? await tmdb.getNetwork(id: entry.id) else { continue }
            rememberEntity(AskEntityCard(kind: .network, tmdbId: network.id, name: network.name, logoPath: network.logoPath))
            rows.append(["ref": "tmdb:network:\(network.id)", "name": network.name, "kind": "TV network"])
        }
        for company in ((try? await tmdb.searchCompanies(query: query)) ?? []).prefix(4) {
            rememberEntity(AskEntityCard(kind: .company, tmdbId: company.id, name: company.name, logoPath: company.logoPath))
            rows.append(["ref": "tmdb:company:\(company.id)", "name": company.name, "kind": "studio", "country": company.originCountry ?? ""])
        }
        return rows.isEmpty ? "No studio or network found for \"\(query)\"." : Self.json(rows)
    }

    private func titlesFrom(_ data: Data) async -> String {
        note("TMDB")
        let a = Self.args(data)
        let ref = a["ref"] as? String ?? ""
        let parts = ref.split(separator: ":")
        guard parts.count == 3, let id = Int(parts[2]) else { return "Use a tmdb:company:ID or tmdb:network:ID ref." }
        let sort: TMDBDiscoverSort = (a["sort"] as? String) == "newest" ? .newest : .popularity
        let tmdb = await FlixorCore.shared.tmdb
        let isNetwork = parts[1] == "network"
        usedEntities.insert("\(isNetwork ? "network" : "company"):\(id)")
        let type = isNetwork ? "tv" : ((a["type"] as? String) == "tv" ? "tv" : "movie")
        let page: TMDBResultsResponse?
        if isNetwork {
            page = try? await tmdb.discoverByNetwork(networkId: id, sort: sort)
        } else {
            page = try? await tmdb.discoverByCompany(companyId: id, mediaType: type == "tv" ? .tv : .movie, sort: sort)
        }
        guard let results = page?.results, !results.isEmpty else { return "Nothing found." }
        return Self.json(results.prefix(12).map { m -> [String: Any] in
            let card = tmdbCard(m, type: type)
            remember(card)
            return ["ref": card.id, "title": card.item.title, "year": card.item.year ?? 0, "type": type,
                    "rating": ((m.voteAverage ?? 0) * 10).rounded() / 10]
        })
    }

    private func searchCollections(_ data: Data) async -> String {
        note("TMDB")
        let query = Self.args(data)["query"] as? String ?? ""
        let tmdb = await FlixorCore.shared.tmdb
        let matches = ((try? await tmdb.searchCollections(query: query)) ?? []).prefix(2)
        guard !matches.isEmpty else { return "No film series found for \"\(query)\"." }
        var rows: [[String: Any]] = []
        for match in matches {
            guard let details = try? await tmdb.getCollection(id: match.id) else { continue }
            let films = details.sortedByRelease().parts.map { m -> [String: Any] in
                let card = tmdbCard(m, type: "movie")
                remember(card)
                return ["ref": card.id, "title": card.item.title, "year": card.item.year ?? 0]
            }
            let first = details.sortedByRelease().parts.first.map { tmdbCard($0, type: "movie").item }
            rememberEntity(AskEntityCard(kind: .collection, tmdbId: match.id, name: match.name, logoPath: match.posterPath, firstPart: first))
            rows.append(["series": match.name, "films_in_release_order": films])
        }
        return Self.json(rows)
    }

    private func history() async -> String {
        note(String(localized: "your watch history"))
        var rows: [[String: Any]] = []
        let trakt = await FlixorCore.shared.trakt
        if await trakt.isAuthenticated, let items = try? await trakt.getHistory(page: 1, limit: 25) {
            for item in items {
                if let movie = item.movie {
                    var row: [String: Any] = ["title": movie.title, "year": movie.year ?? 0, "type": "movie", "watched": String(item.watchedAt.prefix(10))]
                    if let id = movie.ids.tmdb { row["ref"] = "tmdb:movie:\(id)"; await rememberTMDB(id: id, type: "movie") }
                    rows.append(row)
                } else if let show = item.show, let ep = item.episode {
                    var row: [String: Any] = ["title": show.title, "type": "tv", "episode": "S\(ep.season) E\(ep.number)", "watched": String(item.watchedAt.prefix(10))]
                    if let id = show.ids.tmdb { row["ref"] = "tmdb:tv:\(id)"; await rememberTMDB(id: id, type: "tv") }
                    rows.append(row)
                }
            }
        }
        if rows.isEmpty {
            for entry in await LocalLibraryStore.shared.watchHistory().prefix(25) {
                let type = entry.mediaType == .movie ? "movie" : "tv"
                var row: [String: Any] = ["title": entry.title, "type": type]
                if let s = entry.seasonNumber, let e = entry.episodeNumber { row["episode"] = "S\(s) E\(e)" }
                if let id = entry.tmdbId { row["ref"] = "tmdb:\(type):\(id)"; await rememberTMDB(id: id, type: type) }
                rows.append(row)
            }
        }
        return rows.isEmpty ? "No watch history yet." : Self.json(rows)
    }

    private func upcoming() async -> String {
        note(String(localized: "Upcoming"))
        let list = await MainActor.run { () -> [UpcomingEpisode] in
            UpcomingEpisodesStore.shared.refreshIfStale()
            return UpcomingEpisodesStore.shared.episodes
        }
        guard !list.isEmpty else { return "No new or upcoming episodes in the next 30 days." }
        for ep in list.prefix(15) where found["tmdb:tv:\(ep.showTmdbId)"] == nil {
            remember(AskTitleCard(
                item: ep.showItem,
                posterURL: ep.posterURL.flatMap(URL.init(string:)),
                subtitle: ep.isNewUnwatched
                    ? String(localized: "New · \(ep.episodeCode)")
                    : "\(ep.episodeCode) · \(UpcomingLabels.chip(for: ep))"
            ))
        }
        return Self.json(list.prefix(15).map { ep -> [String: Any] in
            [
                "show": ep.showTitle, "ref": "tmdb:tv:\(ep.showTmdbId)", "episode": ep.episodeCode,
                "title": ep.title ?? "",
                "airs": ep.hasTime
                    ? DateFormatter.localizedString(from: ep.airDate, dateStyle: .medium, timeStyle: .short) + " (viewer's local time)"
                    : DateFormatter.localizedString(from: ep.airDate, dateStyle: .medium, timeStyle: .none),
                "new_unwatched": ep.isNewUnwatched
            ]
        })
    }
}

/// Builds a TMDBMedia from details, for one card code path.
private struct TMDBMediaShim {
    let id: Int
    let title: String?
    let name: String?
    let posterPath: String?
    let backdropPath: String?
    let date: String?
    let vote: Double?
    let overview: String?

    var media: TMDBMedia {
        var dict: [String: Any] = ["id": id]
        if let title { dict["title"] = title }
        if let name { dict["name"] = name }
        if let posterPath { dict["poster_path"] = posterPath }
        if let backdropPath { dict["backdrop_path"] = backdropPath }
        if let date { dict["release_date"] = date; dict["first_air_date"] = date }
        if let vote { dict["vote_average"] = vote }
        if let overview { dict["overview"] = overview }
        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{\"id\":\(id)}".utf8)
        return (try? JSONDecoder().decode(TMDBMedia.self, from: data))
            ?? (try! JSONDecoder().decode(TMDBMedia.self, from: Data("{\"id\":\(id)}".utf8)))
    }
}
