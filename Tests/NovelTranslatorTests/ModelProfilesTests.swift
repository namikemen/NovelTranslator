import Testing
import Foundation
@testable import NovelTranslator

@Suite("Multi-Model Profiles & Fallback Chain Tests", .serialized)
struct ModelProfilesTests {

    @Test("LLMConfig encodes and decodes with new profile attributes")
    func testProfileSerialization() throws {
        let profile = LLMConfig(
            id: UUID(),
            name: "DeepSeek Primary",
            baseURL: "https://api.deepseek.com/v1",
            apiKey: "sk-secret-123",
            modelName: "deepseek-chat",
            temperature: 0.2,
            concurrency: 5,
            isEnabled: true
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(LLMConfig.self, from: data)

        #expect(decoded.id == profile.id)
        #expect(decoded.name == "DeepSeek Primary")
        #expect(decoded.baseURL == "https://api.deepseek.com/v1")
        #expect(decoded.apiKey == "sk-secret-123")
        #expect(decoded.modelName == "deepseek-chat")
        #expect(decoded.temperature == 0.2)
        #expect(decoded.concurrency == 5)
        #expect(decoded.isEnabled == true)
    }

    @Test("Backward-compatible decoding when id, name, or isEnabled are omitted in older JSON")
    func testLegacyJSONDecoding() throws {
        let legacyJSON = """
        {
            "baseURL": "https://api.openai.com/v1",
            "apiKey": "sk-legacy",
            "modelName": "gpt-4o",
            "temperature": 0.0,
            "concurrency": 4
        }
        """

        let data = legacyJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LLMConfig.self, from: data)

        #expect(decoded.baseURL == "https://api.openai.com/v1")
        #expect(decoded.apiKey == "sk-legacy")
        #expect(decoded.modelName == "gpt-4o")
        #expect(decoded.name == "Model Profile")
        #expect(decoded.isEnabled == true)
        #expect(decoded.concurrency == 4)
    }

    @Test("EnvConfigManager loads default presets and persists custom profiles")
    func testEnvConfigProfilesPersistence() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_profiles_\(UUID().uuidString).json")
        EnvConfigManager.customProfilesURL = tempURL
        defer {
            EnvConfigManager.customProfilesURL = nil
            try? FileManager.default.removeItem(at: tempURL)
        }

        let profiles = EnvConfigManager.loadModelProfiles()
        #expect(!profiles.isEmpty)

        var customList = profiles
        let newCustom = LLMConfig(
            name: "Test Custom Profile \(UUID().uuidString.prefix(6))",
            baseURL: "http://127.0.0.1:11434/v1",
            apiKey: "",
            modelName: "llama3:latest",
            isEnabled: true
        )
        customList.append(newCustom)

        let saved = EnvConfigManager.saveModelProfiles(customList)
        #expect(saved == true)

        let reloaded = EnvConfigManager.loadModelProfiles()
        #expect(reloaded.contains(where: { $0.id == newCustom.id }))
    }

    @Test("TranslationViewModel manages profile selection, priority reordering, and fallback chain")
    @MainActor
    func testViewModelProfileManagement() {
        let vm = TranslationViewModel(autoRestoreCheckpoint: false)

        let initialCount = vm.modelProfiles.count
        #expect(initialCount >= 1)

        // Add two test profiles
        let p1 = LLMConfig(
            name: "Priority A",
            baseURL: "http://example.com/a",
            apiKey: "key-a",
            modelName: "model-a",
            isEnabled: true
        )
        let p2 = LLMConfig(
            name: "Priority B",
            baseURL: "http://example.com/b",
            apiKey: "key-b",
            modelName: "model-b",
            isEnabled: true
        )

        vm.addModelProfile(p1)
        vm.addModelProfile(p2)

        #expect(vm.modelProfiles.contains(where: { $0.id == p1.id }))
        #expect(vm.modelProfiles.contains(where: { $0.id == p2.id }))

        // Select p1 as active
        vm.selectModelProfile(id: p1.id)
        #expect(vm.activeProfileId == p1.id)
        #expect(vm.activeModelProfile?.id == p1.id)
        #expect(vm.openAIConfig.modelName == "model-a")

        // Active fallback configs should include p2 (since it is enabled and not active)
        vm.autoFallback = true
        let fallbacks = vm.activeFallbackConfigs
        #expect(fallbacks.contains(where: { $0.id == p2.id }))
        #expect(!fallbacks.contains(where: { $0.id == p1.id }))

        // Reordering test
        let idxB = vm.modelProfiles.firstIndex(where: { $0.id == p2.id })!
        vm.moveProfileUp(id: p2.id)
        let newIdxB = vm.modelProfiles.firstIndex(where: { $0.id == p2.id })!
        #expect(newIdxB == idxB - 1)

        // Disable p2 and verify it is removed from active fallbacks
        vm.toggleProfileEnabled(id: p2.id)
        #expect(!vm.activeFallbackConfigs.contains(where: { $0.id == p2.id }))

        // Clean up added test profiles
        vm.deleteModelProfile(id: p1.id)
        vm.deleteModelProfile(id: p2.id)
    }

    @Test("Sequential failover through ordered fallback models in translateBatch")
    func testOrderedFallbackExecution() async throws {
        final class FallbackAudit: @unchecked Sendable {
            var notices: [String] = []
        }
        let audit = FallbackAudit()

        let brokenPrimary = LLMConfig(name: "Model-1", baseURL: "http://127.0.0.1:9991/v1", apiKey: "", modelName: "m1")
        let brokenFallback1 = LLMConfig(name: "Model-2", baseURL: "http://127.0.0.1:9992/v1", apiKey: "", modelName: "m2")
        let brokenFallback2 = LLMConfig(name: "Model-3", baseURL: "http://127.0.0.1:9993/v1", apiKey: "", modelName: "m3")

        let items = [(id: 1, text: "The swift brown fox.")]

        do {
            try await LLMTranslationService.translateBatch(
                items: items,
                from: "English",
                to: "French",
                config: brokenPrimary,
                fallbackConfigs: [brokenFallback1, brokenFallback2],
                onFallbackUsed: { id, notice in
                    audit.notices.append(notice)
                },
                onItemCompleted: { _, _ in }
            )
        } catch {
            // Expected to fail since all mock ports are unconnectable
        }

        #expect(audit.notices.count >= 2)
        #expect(audit.notices[0].contains("Model-2"))
        #expect(audit.notices[1].contains("Model-3"))
    }
}
