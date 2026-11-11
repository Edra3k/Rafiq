import Foundation

// MARK: - The agent guard's words, shared by the Mac, the iPhone and the Watch

extension CommandRisk.Reason {
    /// "Read only", "Deletes", "Force push"…
    var label: String {
        switch self {
        case .readOnly:        return String(localized: "guard.reason.read-only", defaultValue: "Read only")
        case .writesFiles:     return String(localized: "guard.reason.writes", defaultValue: "Edits files")
        case .network:         return String(localized: "guard.reason.network", defaultValue: "Network")
        case .installs:        return String(localized: "guard.reason.installs", defaultValue: "Installs")
        case .runsCode:        return String(localized: "guard.reason.runs-code", defaultValue: "Runs code")
        case .publishes:       return String(localized: "guard.reason.publishes", defaultValue: "Publishes")
        case .unknown:         return String(localized: "guard.reason.unknown", defaultValue: "Check it")
        case .deletes:         return String(localized: "guard.reason.deletes", defaultValue: "Deletes")
        case .forcePush:       return String(localized: "guard.reason.force-push", defaultValue: "Force push")
        case .rewritesHistory: return String(localized: "guard.reason.history", defaultValue: "Rewrites history")
        case .pipeToShell:     return String(localized: "guard.reason.pipe", defaultValue: "Runs downloaded code")
        case .privilege:       return String(localized: "guard.reason.admin", defaultValue: "Admin rights")
        case .secrets:         return String(localized: "guard.reason.secrets", defaultValue: "Secrets")
        case .systemConfig:    return String(localized: "guard.reason.system", defaultValue: "System settings")
        }
    }

    /// One line saying what the action can do.
    var explanation: String {
        switch self {
        case .readOnly:        return String(localized: "guard.why.read-only", defaultValue: "Changes nothing")
        case .writesFiles:     return String(localized: "guard.why.writes", defaultValue: "Changes files in the project")
        case .network:         return String(localized: "guard.why.network", defaultValue: "Talks to a server")
        case .installs:        return String(localized: "guard.why.installs", defaultValue: "Adds packages to the machine")
        case .runsCode:        return String(localized: "guard.why.runs-code", defaultValue: "Starts a program")
        case .publishes:       return String(localized: "guard.why.publishes", defaultValue: "Sends your work outside")
        case .unknown:         return String(localized: "guard.why.unknown", defaultValue: "A command the guard does not know")
        case .deletes:         return String(localized: "guard.why.deletes", defaultValue: "Can erase files for good")
        case .forcePush:       return String(localized: "guard.why.force-push", defaultValue: "Rewrites the remote history")
        case .rewritesHistory: return String(localized: "guard.why.history", defaultValue: "Rewrites the Git history")
        case .pipeToShell:     return String(localized: "guard.why.pipe", defaultValue: "Runs a script straight from the internet")
        case .privilege:       return String(localized: "guard.why.admin", defaultValue: "Asks for administrator rights")
        case .secrets:         return String(localized: "guard.why.secrets", defaultValue: "Touches keys, tokens or passwords")
        case .systemConfig:    return String(localized: "guard.why.system", defaultValue: "Changes how the Mac works")
        }
    }
}

extension CommandRisk.Level {
    /// Green, amber, red.
    var hex: String {
        switch self {
        case .safe:    return "#34D399"
        case .caution: return "#F5A524"
        case .high:    return "#F4505E"
        }
    }

    /// SF Symbol for the level.
    var symbol: String {
        switch self {
        case .safe:    return "checkmark.shield.fill"
        case .caution: return "eye.fill"
        case .high:    return "exclamationmark.triangle.fill"
        }
    }
}
