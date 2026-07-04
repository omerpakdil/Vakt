import Supabase

extension SupabaseBackendConfiguration {
    func makeClient() -> SupabaseClient {
        SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)
    }
}
