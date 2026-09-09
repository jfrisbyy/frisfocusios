//
//  TaskTuneAI.swift
//  FrisFocus
//
//  Thin client for the `task-tune` edge function — the scoped "talk it
//  through" about ONE slipping task or milestone. The coaching prompt,
//  the model key, and the proposal whitelist all live on the backend;
//  the app sends the item's real numbers plus the running chat and gets
//  back a short reply with 0-3 TYPED changes it can apply on tap.
//
//  Nothing here mutates anything: proposals are inert until the person
//  taps one, and applying them is the sheet's job, through the Store's
//  ordinary editing paths.
//

import Foundation

// MARK: - Wire types

/// The one item under discussion, flattened to the numbers the coach
/// is allowed to reason from. Encodable keys mirror the function's
/// context contract.
nonisolated struct TaskTuneItem: Encodable, Sendable {
    let kind: String            // "task" | "milestone"
    let name: String
    let value: Int
    let estMinutes: Int?
    let schedule: String        // human-readable: "Mon, Wed, Fri" / "every day" / "unscheduled"
    let daysSinceTouched: Int?
    let weekCount: Int          // completions in the current week
    let seasonDay: Int
    let dailyGoal: Int
    let targetDate: String?     // milestone
    let stepsTotal: Int?
    let stepsDone: Int?

    enum CodingKeys: String, CodingKey {
        case kind, name, value, schedule
        case estMinutes = "est_minutes"
        case daysSinceTouched = "days_since_touched"
        case weekCount = "week_count"
        case seasonDay = "season_day"
        case dailyGoal = "daily_goal"
        case targetDate = "target_date"
        case stepsTotal = "steps_total"
        case stepsDone = "steps_done"
    }
}

/// A typed change the coach proposed. Only shapes the server
/// whitelisted can decode; anything else becomes `.unsupported` and is
/// never shown.
nonisolated enum TaskTuneChange: Sendable, Equatable {
    case reschedule(days: Set<Int>)
    case shrink(estMinutes: Int, name: String?)
    case reprice(value: Int)
    case pause(days: Int)
    case drop
    case pushDate(Date)
    case addStep(title: String)
    case unsupported
}

nonisolated struct TaskTuneProposal: Decodable, Identifiable, Sendable {
    let label: String
    let detail: String
    let change: TaskTuneChange

    var id: String { label + detail }

    enum CodingKeys: String, CodingKey { case label, detail, change }
    enum ChangeKeys: String, CodingKey {
        case action, days, value, name, title
        case estMinutes = "est_minutes"
        case targetDate = "target_date"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? "Apply"
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""

        let ch = try c.nestedContainer(keyedBy: ChangeKeys.self, forKey: .change)
        let action = try ch.decodeIfPresent(String.self, forKey: .action) ?? ""
        switch action {
        case "reschedule":
            let days = try ch.decodeIfPresent([Int].self, forKey: .days) ?? []
            change = .reschedule(days: Set(days.filter { (1...7).contains($0) }))
        case "shrink":
            let minutes = try ch.decodeIfPresent(Int.self, forKey: .estMinutes) ?? 15
            let newName = try ch.decodeIfPresent(String.self, forKey: .name)
            change = .shrink(estMinutes: max(1, min(600, minutes)), name: newName)
        case "reprice":
            let value = try ch.decodeIfPresent(Int.self, forKey: .value) ?? 1
            change = .reprice(value: value)
        case "pause":
            let days = try ch.decodeIfPresent(Int.self, forKey: .days) ?? 7
            change = .pause(days: max(1, min(14, days)))
        case "drop":
            change = .drop
        case "push_date":
            let raw = try ch.decodeIfPresent(String.self, forKey: .targetDate) ?? ""
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            change = formatter.date(from: raw).map(TaskTuneChange.pushDate) ?? .unsupported
        case "add_step":
            let title = try ch.decodeIfPresent(String.self, forKey: .title) ?? ""
            change = title.isEmpty ? .unsupported : .addStep(title: title)
        default:
            change = .unsupported
        }
    }
}

nonisolated struct TaskTuneReply: Decodable, Sendable {
    let message: String
    let proposals: [TaskTuneProposal]
    let done: Bool
    /// The model's raw output, replayed verbatim as the assistant turn
    /// so it keeps full context of its own proposals.
    let raw: String

    /// Proposals the app can actually act on.
    var actionable: [TaskTuneProposal] {
        proposals.filter { $0.change != .unsupported }
    }
}

// MARK: - Transport

nonisolated enum TaskTuneAIError: LocalizedError {
    case notSignedIn
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You need to be signed in to talk this through."
        case .server(let message): return message
        case .badResponse: return "The coach returned an unexpected response."
        }
    }
}

private nonisolated struct TuneRequestBody: Encodable, Sendable {
    let messages: [AIMessage]
    let item: TaskTuneItem
}

private nonisolated struct TuneErrorBody: Decodable, Sendable {
    let error: String?
}

enum TaskTuneAI {
    private nonisolated static var functionURL: URL {
        URL(string: "\(Config.EXPO_PUBLIC_SUPABASE_URL)/functions/v1/task-tune")!
    }

    /// Send the item + running history; receive the next coaching turn.
    /// An empty history asks the coach to open the conversation.
    nonisolated static func send(
        item: TaskTuneItem,
        history: [AIMessage]
    ) async throws -> TaskTuneReply {
        guard let token = KeychainHelper.get("access_token"), !token.isEmpty else {
            throw TaskTuneAIError.notSignedIn
        }
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.EXPO_PUBLIC_SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90
        request.httpBody = try JSONEncoder().encode(TuneRequestBody(messages: history, item: item))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TaskTuneAIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let decoded = try? JSONDecoder().decode(TuneErrorBody.self, from: data),
               let message = decoded.error, !message.isEmpty {
                throw TaskTuneAIError.server(message)
            }
            throw TaskTuneAIError.server("The coach couldn't answer (\(http.statusCode)).")
        }
        do {
            return try JSONDecoder().decode(TaskTuneReply.self, from: data)
        } catch {
            Log.app.error("task-tune decode failed: \(error)")
            throw TaskTuneAIError.badResponse
        }
    }
}
