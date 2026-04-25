import Foundation

// Copy this file to `Configuration.swift` (gitignored) and fill in the values.
// Only the supabase URL and anon key are needed in the app — all secret keys
// (OpenAI, Gemini, Tavily, Gradium, Hera) live as supabase function secrets.
enum Configuration {
    static let supabaseURL: URL = URL(string: "https://YOUR_PROJECT.supabase.co")!
    static let supabaseAnonKey: String = "YOUR_ANON_KEY"
}
