import Foundation

enum WorksheetAction: String, Codable, CaseIterable, Identifiable {
    case correct
    case complete
    case fillOut = "fill_out"
    case annotate
    case schriftReplace = "schrift_replace"
    case explainVideo = "explain_video"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .correct: return "Correct"
        case .complete: return "Complete"
        case .fillOut: return "Fill out"
        case .annotate: return "Annotate"
        case .schriftReplace: return "Replace handwriting"
        case .explainVideo: return "Explainer video"
        }
    }

    var subtitle: String {
        switch self {
        case .correct: return "Mark mistakes, write fixes"
        case .complete: return "Finish the unfinished"
        case .fillOut: return "Write all answers"
        case .annotate: return "Notes, hints, underlines"
        case .schriftReplace: return "Same words, your script"
        case .explainVideo: return "Walk me through it"
        }
    }

    var systemImage: String {
        switch self {
        case .correct: return "checkmark.seal"
        case .complete: return "square.and.pencil"
        case .fillOut: return "pencil.and.list.clipboard"
        case .annotate: return "highlighter"
        case .schriftReplace: return "textformat.alt"
        case .explainVideo: return "play.rectangle"
        }
    }

    /// True if the action operates on uploaded worksheet images.
    var requiresImages: Bool {
        switch self {
        case .correct, .complete, .fillOut, .annotate, .schriftReplace: return true
        case .explainVideo: return false
        }
    }

    /// schrift_replace doesn't make sense with adaptive mode (would replace handwriting with itself).
    /// explain_video doesn't use handwriting at all.
    var supportsAdaptiveMode: Bool {
        switch self {
        case .schriftReplace, .explainVideo: return false
        default: return true
        }
    }
}

enum HandwritingMode: String, Codable {
    case library
    case adaptive
}
