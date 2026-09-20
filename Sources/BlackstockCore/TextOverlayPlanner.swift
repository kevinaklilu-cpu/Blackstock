import Foundation

public struct TextOverlayCue: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let startSeconds: Double
    public let durationSeconds: Double
    public let text: String
    public let normalizedYFromTop: Double

    public init(
        id: UUID,
        startSeconds: Double,
        durationSeconds: Double,
        text: String,
        normalizedYFromTop: Double
    ) {
        self.id = id
        self.startSeconds = max(startSeconds, 0)
        self.durationSeconds = max(durationSeconds, 0)
        self.text = text
        self.normalizedYFromTop = min(
            max(normalizedYFromTop, 0.05),
            0.95
        )
    }
}

public struct TextOverlayPlanner: Sendable {
    public init() {}

    public func cues(
        operations: [EditOperation],
        outputDurationSeconds: Double
    ) -> [TextOverlayCue] {
        let outputDuration = max(outputDurationSeconds, 0)
        guard outputDuration > 0 else { return [] }

        let lastStructuralEditIndex = operations.lastIndex {
            $0.type == .trim || $0.type == .removeRange
        }
        let activeOperations: ArraySlice<EditOperation>
        if let lastStructuralEditIndex {
            activeOperations = operations[
                operations.index(after: lastStructuralEditIndex)...
            ]
        } else {
            activeOperations = operations[...]
        }

        return activeOperations.compactMap { operation in
            guard operation.type == .overlay,
                  let range = operation.timeRange else {
                return nil
            }

            let text = operation.text?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""
            guard !text.isEmpty else { return nil }

            let start = min(
                max(range.startSeconds, 0),
                outputDuration
            )
            let end = min(
                max(range.endSeconds, start),
                outputDuration
            )
            guard end - start >= 0.05 else {
                return nil
            }

            return TextOverlayCue(
                id: operation.id,
                startSeconds: start,
                durationSeconds: end - start,
                text: text,
                normalizedYFromTop: operation.value ?? 0.18
            )
        }
    }
}
