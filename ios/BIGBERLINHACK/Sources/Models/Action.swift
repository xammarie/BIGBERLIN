import Foundation

enum WorksheetAction: String, Codable, CaseIterable, Identifiable {
    case correct
    case complete
    case fillOut = "fill_out"
    case annotate
    case schriftReplace = "schrift_replace"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .correct: return "Correct"
        case .complete: return "Complete"
        case .fillOut: return "Fill out"
        case .annotate: return "Annotate"
        case .schriftReplace: return "Replace handwriting"
        }
    }

    var subtitle: String {
        switch self {
        case .correct: return "Mark mistakes, write fixes"
        case .complete: return "Finish the unfinished parts"
        case .fillOut: return "Write all answers"
        case .annotate: return "Add notes, hints, underlines"
        case .schriftReplace: return "Same words, your handwriting"
        }
    }

    var systemImage: String {
        switch self {
        case .correct: return "checkmark.seal"
        case .complete: return "square.and.pencil"
        case .fillOut: return "pencil.and.list.clipboard"
        case .annotate: return "highlighter"
        case .schriftReplace: return "textformat.alt"
        }
    }

    /// schrift_replace doesn't make sense with adaptive mode (would replace handwriting with itself).
    var supportsAdaptiveMode: Bool {
        self != .schriftReplace
    }
}

enum HandwritingMode: String, Codable {
    case library
    case adaptive
}
