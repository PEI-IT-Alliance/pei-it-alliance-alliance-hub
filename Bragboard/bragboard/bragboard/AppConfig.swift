//
//  AppConfig.swift
//  bragboard
//
//  Manages app configuration and secure API keys
//  🔐 This file READS from Config.plist (which should be .gitignored)
//

import Foundation

struct AppConfig {
    static let shared = AppConfig()
    
    private init() {}
    
    // MARK: - Configuration Keys
    private enum ConfigKey: String {
        case locariusAPIToken = "LocariusAPIToken"
        case nightShiftTVKey = "NightShiftTVKey"
    }
    
    // MARK: - Config Loading
    private var configDictionary: [String: Any] {
        // Debug: Print all possible plist locations
        print("🔍 Looking for Config.plist...")
        
        if let path = Bundle.main.path(forResource: "Config", ofType: "plist") {
            print("✅ Found Config.plist at: \(path)")
            
            if let dict = NSDictionary(contentsOfFile: path) as? [String: Any] {
                print("✅ Successfully loaded Config.plist")
                print("📋 Keys in config: \(dict.keys)")
                
                // Check if token key exists
                if let token = dict["LocariusAPIToken"] as? String {
                    print("✅ Found LocariusAPIToken key")
                    if token.isEmpty || token == "YOUR_TOKEN_HERE" {
                        print("⚠️ Token is empty or placeholder")
                    } else {
                        print("✅ Token is configured (length: \(token.count))")
                    }
                } else {
                    print("❌ LocariusAPIToken key not found in plist")
                }
                
                return dict
            } else {
                print("❌ Failed to parse Config.plist as dictionary")
            }
        } else {
            print("❌ Config.plist not found in bundle")
            print("📍 Bundle path: \(Bundle.main.bundlePath)")
        }
        
        print("⚠️ Using empty config dictionary")
        return [:]
    }
    
    // MARK: - API Tokens
    
    /// Locarius API token for fetching events
    /// This should be stored in Config.plist (not committed to git)
    var locariusAPIToken: String {
        print("🔑 Attempting to read Locarius API token...")
        
        if let token = configDictionary[ConfigKey.locariusAPIToken.rawValue] as? String {
            print("✅ Token found in config")
            
            if token.isEmpty {
                print("⚠️ Token is empty string")
                return ""
            }
            
            if token == "YOUR_TOKEN_HERE" {
                print("⚠️ Token is still placeholder value")
                return ""
            }
            
            print("✅ Token is valid (length: \(token.count))")
            return token
        }
        
        print("❌ Token key not found in config dictionary")
        print("❌ Available keys: \(configDictionary.keys)")
        return ""
    }
    
    /// Read-only Night Shift TV key for the Foundry feed.
    /// Config.plist only — never in code or CloudKit, and never printed.
    var nightShiftTVKey: String {
        let key = configDictionary[ConfigKey.nightShiftTVKey.rawValue] as? String ?? ""
        return key == "YOUR_TOKEN_HERE" ? "" : key
    }

    // MARK: - Validation
    
    /// Check if Locarius API is properly configured
    var isLocariusConfigured: Bool {
        !locariusAPIToken.isEmpty && locariusAPIToken != "YOUR_TOKEN_HERE"
    }
}
