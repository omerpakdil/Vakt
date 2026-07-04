import Foundation
import Supabase

enum SupabaseBackendErrorMapper {
    static func map(_ error: Error) -> BackendError {
        if let backendError = error as? BackendError {
            return backendError
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost:
                return .offline
            case .cancelled:
                return .cancelled
            default:
                return .server(message: urlError.localizedDescription)
            }
        }
        if let postgrestError = error as? PostgrestError {
            switch postgrestError.code {
            case "28000": return .unauthenticated
            case "42501": return .forbidden
            case "P0002": return .sessionUnavailable
            case "23505": return .conflict
            default: return .server(message: postgrestError.message)
            }
        }
        if let authError = error as? AuthError {
            if authError == .sessionMissing {
                return .unauthenticated
            }
            return .server(message: authError.localizedDescription)
        }
        if error is CancellationError {
            return .cancelled
        }
        return .server(message: error.localizedDescription)
    }
}
