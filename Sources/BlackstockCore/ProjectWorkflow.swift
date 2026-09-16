import Foundation

public enum ProjectStage: String, Codable, Sendable, CaseIterable {
    case idea, editing, rendered, packaging, ready
}

public struct ProjectReadinessItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let isComplete: Bool
    public init(id: String, label: String, isComplete: Bool) { self.id = id; self.label = label; self.isComplete = isComplete }
}

public struct ProjectWorkflowEngine: Sendable {
    public init() {}

    public func stage(for project: Project) -> ProjectStage {
        let package = readiness(for: project)
        if package.allSatisfy(\.isComplete) { return .ready }
        if project.renderedOutputURL != nil && !(project.publishTitle ?? "").isEmpty { return .packaging }
        if project.renderedOutputURL != nil { return .rendered }
        if project.localMediaURL != nil || !project.transcript.isEmpty { return .editing }
        return .idea
    }

    public func readiness(for project: Project) -> [ProjectReadinessItem] {
        let publishTitle = (project.publishTitle ?? project.title).trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (project.publishDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            .init(id: "media", label: "Finale Videodatei gerendert", isComplete: project.renderedOutputURL != nil),
            .init(id: "title", label: "Titel festgelegt", isComplete: !publishTitle.isEmpty),
            .init(id: "description", label: "Beschreibung vorbereitet", isComplete: !description.isEmpty),
            .init(id: "thumbnail", label: "Thumbnail vorbereitet", isComplete: project.thumbnailURL != nil)
        ]
    }

    public func clampedRange(for project: Project, duration: Double) -> ClosedRange<Double> {
        let safeDuration = max(duration, 0)
        let start = min(max(project.editInSeconds ?? 0, 0), safeDuration)
        let requestedEnd = project.editOutSeconds ?? safeDuration
        let end = min(max(requestedEnd, start), safeDuration)
        return start...end
    }
}
