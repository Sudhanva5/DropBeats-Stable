import Foundation

enum SupabaseConfig {
    static let projectURL = "https://trtxfdsssreqhuajpvqk.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRydHhmZHNzc3JlcWh1YWpwdnFrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYzNTY5MTIsImV4cCI6MjA1MTkzMjkxMn0.CYDp3xGrlILUsjP2yzT3Y1cFGyACP57R3awfQvs35A4"
    
    static var isConfigured: Bool {
        return !projectURL.isEmpty && !anonKey.isEmpty
    }
} 
