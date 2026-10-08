import Foundation

public struct EnvConfigManager: Sendable {
    private static let envFileName = ".env"

    /// Primary search locations for .env:
    /// 1. Application Support directory
    /// 2. Current working directory / project directory
    public static var appSupportEnvURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("NovelTranslator", isDirectory: true)
        let legacyDir = appSupport.appendingPathComponent("DocTranslateApp", isDirectory: true)

        let targetDir: URL
        if !FileManager.default.fileExists(atPath: appDir.path) && FileManager.default.fileExists(atPath: legacyDir.path) {
            targetDir = legacyDir
        } else {
            targetDir = appDir
            if !FileManager.default.fileExists(atPath: targetDir.path) {
                try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            }
        }
        return targetDir.appendingPathComponent(envFileName)
    }

    public static var projectEnvURL: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(envFileName)
    }

    /// Loads environment key-value pairs from .env files and ProcessInfo.
    public static func loadEnvVariables() -> [String: String] {
        var env: [String: String] = [:]

        // 1. Process environment (lowest priority)
        for (key, value) in ProcessInfo.processInfo.environment {
            env[key] = value
        }

        // 2. Project directory .env
        let projectPath = projectEnvURL.path
        if FileManager.default.fileExists(atPath: projectPath),
           let contents = try? String(contentsOfFile: projectPath, encoding: .utf8) {
            let parsed = parseEnvContent(contents)
            for (k, v) in parsed { env[k] = v }
        }

        // 3. Application Support .env (user-configured in GUI)
        let appSupportPath = appSupportEnvURL.path
        if FileManager.default.fileExists(atPath: appSupportPath),
           let contents = try? String(contentsOfFile: appSupportPath, encoding: .utf8) {
            let parsed = parseEnvContent(contents)
            for (k, v) in parsed { env[k] = v }
        }

        // 4. UserDefaults overlay (preserves GUI changes across restarts)
        let defaults = UserDefaults.standard
        if let baseUrl = defaults.string(forKey: "OPENAI_BASE_URL"), !baseUrl.isEmpty {
            env["OPENAI_BASE_URL"] = baseUrl
        }
        if let apiKey = defaults.string(forKey: "OPENAI_API_KEY"), !apiKey.isEmpty {
            env["OPENAI_API_KEY"] = apiKey
        }
        if let model = defaults.string(forKey: "OPENAI_MODEL"), !model.isEmpty {
            env["OPENAI_MODEL"] = model
        }
        let temp = defaults.double(forKey: "OPENAI_TEMPERATURE")
        if temp > 0 {
            env["OPENAI_TEMPERATURE"] = String(temp)
        }
        let concurrency = defaults.integer(forKey: "OPENAI_CONCURRENCY")
        if concurrency > 0 {
            env["OPENAI_CONCURRENCY"] = String(concurrency)
        }

        return env
    }

    /// Loads OpenAI LLMConfig from environment variables / .env / UserDefaults
    public static func loadOpenAIConfig() -> LLMConfig {
        let env = loadEnvVariables()
        var config = LLMConfig.defaultOpenAI

        if let base = env["OPENAI_BASE_URL"], !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.baseURL = base.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let key = env["OPENAI_API_KEY"] {
            config.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let model = env["OPENAI_MODEL"] ?? env["OPENAI_MODEL_NAME"], !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let tempStr = env["OPENAI_TEMPERATURE"], let temp = Double(tempStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
            config.temperature = max(0.0, min(2.0, temp))
        }
        if let concStr = env["OPENAI_CONCURRENCY"], let conc = Int(concStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
            config.concurrency = max(1, min(10, conc))
        }

        return config
    }

    /// Loads only on-disk .env variables (without ProcessInfo)
    public static func loadDiskEnvVariables() -> [String: String] {
        var env: [String: String] = [:]

        let projectPath = projectEnvURL.path
        if FileManager.default.fileExists(atPath: projectPath),
           let contents = try? String(contentsOfFile: projectPath, encoding: .utf8) {
            let parsed = parseEnvContent(contents)
            for (k, v) in parsed { env[k] = v }
        }

        let appSupportPath = appSupportEnvURL.path
        if FileManager.default.fileExists(atPath: appSupportPath),
           let contents = try? String(contentsOfFile: appSupportPath, encoding: .utf8) {
            let parsed = parseEnvContent(contents)
            for (k, v) in parsed { env[k] = v }
        }

        return env
    }

    /// Saves OpenAI LLMConfig to .env file in Application Support and project folder (if writable), plus UserDefaults
    @discardableResult
    public static func saveOpenAIConfig(_ config: LLMConfig) -> Bool {
        // Save to UserDefaults
        let defaults = UserDefaults.standard
        defaults.set(config.baseURL, forKey: "OPENAI_BASE_URL")
        defaults.set(config.apiKey, forKey: "OPENAI_API_KEY")
        defaults.set(config.modelName, forKey: "OPENAI_MODEL")
        defaults.set(config.temperature, forKey: "OPENAI_TEMPERATURE")
        defaults.set(config.concurrency, forKey: "OPENAI_CONCURRENCY")

        // Read existing disk .env (or create fresh)
        var env = loadDiskEnvVariables()
        env["OPENAI_BASE_URL"] = config.baseURL
        env["OPENAI_API_KEY"] = config.apiKey
        env["OPENAI_MODEL"] = config.modelName
        env["OPENAI_TEMPERATURE"] = String(format: "%.2f", config.temperature)
        env["OPENAI_CONCURRENCY"] = String(config.concurrency)

        let content = serializeEnv(env)

        var success = false
        // Write to Application Support .env
        do {
            try content.write(to: appSupportEnvURL, atomically: true, encoding: .utf8)
            success = true
        } catch {
            print("Failed to save .env to Application Support: \(error)")
        }

        // Also try writing to project .env if current directory is writable
        let projectPath = projectEnvURL.path
        if FileManager.default.isWritableFile(atPath: (projectPath as NSString).deletingLastPathComponent) {
            try? content.write(to: projectEnvURL, atomically: true, encoding: .utf8)
        }

        return success
    }

    /// Parses KEY=VALUE format with comments (#) and quotes
    public static func parseEnvContent(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Look for first '='
            if let equalIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                var value = String(trimmed[trimmed.index(after: equalIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)

                // Handle quotes
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    if value.count >= 2 {
                        value = String(value.dropFirst().dropLast())
                    }
                }

                if !key.isEmpty {
                    result[key] = value
                }
            }
        }
        return result
    }

    /// Serializes dictionary to clean .env string
    public static func serializeEnv(_ env: [String: String]) -> String {
        var lines: [String] = [
            "# NovelTranslator Configuration",
            "# Automatically saved on \(ISO8601DateFormatter().string(from: Date()))",
            ""
        ]

        let orderedKeys = [
            "OPENAI_BASE_URL",
            "OPENAI_API_KEY",
            "OPENAI_MODEL",
            "OPENAI_TEMPERATURE",
            "OPENAI_CONCURRENCY",
            "OLLAMA_BASE_URL",
            "OLLAMA_MODEL",
            "OLLAMA_CONCURRENCY"
        ]

        var remainingKeys = Set(env.keys)

        for key in orderedKeys {
            if let value = env[key] {
                // If value has spaces or special chars, quote it
                let needsQuote = value.contains(" ") || value.contains("#")
                let formattedVal = needsQuote ? "\"\(value)\"" : value
                lines.append("\(key)=\(formattedVal)")
                remainingKeys.remove(key)
            }
        }

        // Add any remaining keys
        for key in remainingKeys.sorted() {
            if let value = env[key] {
                let needsQuote = value.contains(" ") || value.contains("#")
                let formattedVal = needsQuote ? "\"\(value)\"" : value
                lines.append("\(key)=\(formattedVal)")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Prompt Storage
    public static func loadPrompts() -> (translation: String?, characterAnalysis: String?) {
        let defaults = UserDefaults.standard
        let trans = defaults.string(forKey: "CUSTOM_TRANSLATION_PROMPT")
        let char = defaults.string(forKey: "CUSTOM_CHARACTER_ANALYSIS_PROMPT")
        return (trans, char)
    }

    public static func savePrompts(translation: String, characterAnalysis: String) {
        let defaults = UserDefaults.standard
        defaults.set(translation, forKey: "CUSTOM_TRANSLATION_PROMPT")
        defaults.set(characterAnalysis, forKey: "CUSTOM_CHARACTER_ANALYSIS_PROMPT")
    }

    // MARK: - Batch Word Limit
    public static let batchWordLimitKey = "EPUB_BATCH_WORD_LIMIT"

    public static func loadBatchWordLimit() -> Int {
        let saved = UserDefaults.standard.integer(forKey: batchWordLimitKey)
        if saved >= 500 {
            return min(max(500, saved), 2500)
        }
        if let envVal = loadEnvVariables()[batchWordLimitKey], let parsed = Int(envVal), parsed >= 500 {
            return min(max(500, parsed), 2500)
        }
        return 1200
    }

    public static func saveBatchWordLimit(_ limit: Int) {
        let safeLimit = min(max(500, limit), 2500)
        UserDefaults.standard.set(safeLimit, forKey: batchWordLimitKey)
    }

    // MARK: - Model Profiles Storage
    nonisolated(unsafe) public static var customProfilesURL: URL? = nil

    public static var profilesURL: URL {
        if let custom = customProfilesURL {
            return custom
        }
        return appSupportProfilesURL
    }

    public static var appSupportProfilesURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("NovelTranslator", isDirectory: true)
        let legacyDir = appSupport.appendingPathComponent("DocTranslateApp", isDirectory: true)

        let targetDir: URL
        if !FileManager.default.fileExists(atPath: appDir.path) && FileManager.default.fileExists(atPath: legacyDir.path) {
            targetDir = legacyDir
        } else {
            targetDir = appDir
            if !FileManager.default.fileExists(atPath: targetDir.path) {
                try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            }
        }
        return targetDir.appendingPathComponent("model_profiles.json")
    }

    public static func loadModelProfiles() -> [LLMConfig] {
        // 1. Check file in Application Support / customProfilesURL
        if FileManager.default.fileExists(atPath: profilesURL.path),
           let data = try? Data(contentsOf: profilesURL),
           let profiles = try? JSONDecoder().decode([LLMConfig].self, from: data),
           !profiles.isEmpty {
            return profiles
        }

        // 2. Check UserDefaults
        if customProfilesURL == nil,
           let data = UserDefaults.standard.data(forKey: "SAVED_MODEL_PROFILES"),
           let profiles = try? JSONDecoder().decode([LLMConfig].self, from: data),
           !profiles.isEmpty {
            return profiles
        }

        // 3. Migration: Build initial profiles from existing openAIConfig & default presets
        let existingOpenAI = loadOpenAIConfig()
        var primaryProfile = existingOpenAI
        let hasCustomOpenAI = !existingOpenAI.baseURL.isEmpty && (!existingOpenAI.apiKey.isEmpty || existingOpenAI.baseURL != "https://api.openai.com/v1")
        primaryProfile.name = hasCustomOpenAI ? "Primary (\(existingOpenAI.modelName))" : "OpenAI (Primary)"
        primaryProfile.isEnabled = true

        var ollamaProfile = LLMConfig.defaultOllama
        ollamaProfile.isEnabled = true

        var deepseekPreset = LLMConfig.presetDeepSeek
        deepseekPreset.isEnabled = false

        var openrouterPreset = LLMConfig.presetOpenRouter
        openrouterPreset.isEnabled = false

        let initialProfiles: [LLMConfig] = [
            primaryProfile,
            ollamaProfile,
            deepseekPreset,
            openrouterPreset
        ]

        saveModelProfiles(initialProfiles)
        return initialProfiles
    }

    @discardableResult
    public static func saveModelProfiles(_ profiles: [LLMConfig]) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(profiles) else { return false }
        if customProfilesURL == nil {
            UserDefaults.standard.set(data, forKey: "SAVED_MODEL_PROFILES")
        }
        let targetURL = profilesURL
        let parentDir = targetURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        do {
            try data.write(to: targetURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public static func loadActiveProfileId() -> UUID? {
        if let str = UserDefaults.standard.string(forKey: "ACTIVE_MODEL_PROFILE_ID"),
           let id = UUID(uuidString: str) {
            return id
        }
        return nil
    }

    public static func saveActiveProfileId(_ id: UUID?) {
        if let id = id {
            UserDefaults.standard.set(id.uuidString, forKey: "ACTIVE_MODEL_PROFILE_ID")
        } else {
            UserDefaults.standard.removeObject(forKey: "ACTIVE_MODEL_PROFILE_ID")
        }
    }
}
