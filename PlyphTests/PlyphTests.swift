import XCTest
@testable import Plyph

final class PlyphTests: XCTestCase {
    func testBuiltInCorrectUsesTransformationMode() {
        let request = BuiltInAction.correct.request(settings: AppSettings())
        XCTAssertEqual(request.label, "Correct")
        XCTAssertEqual(request.inputMode, .transform)
    }

    func testRunPromptCarriesOverrides() {
        var settings = AppSettings()
        settings.runProviderID = Provider.openai.id
        settings.runModel = "example-model"
        settings.runInputLimit = 100
        settings.runOutputLimit = 200

        let request = BuiltInAction.runPrompt.request(settings: settings)
        XCTAssertEqual(request.inputMode, .prompt)
        XCTAssertEqual(request.providerID, Provider.openai.id)
        XCTAssertEqual(request.model, "example-model")
        XCTAssertEqual(request.inputLimit, 100)
        XCTAssertEqual(request.outputLimit, 200)
    }

    func testProviderDefaultsAreNotEmpty() {
        for provider in Provider.allCases where provider != .customOpenAI {
            XCTAssertFalse(provider.defaultModel.isEmpty)
        }
    }

    func testCustomProviderRequiresAnExplicitModel() {
        XCTAssertEqual(Provider.customOpenAI.defaultModel, "")
        XCTAssertFalse(Provider.customOpenAI.requiresAPIKey)
        XCTAssertTrue(Provider.customOpenAI.supportsAPIKey)
    }

    func testCloudflareDefaultsToReasoningOff() {
        let settings = AppSettings()

        XCTAssertEqual(
            settings.model(for: .cloudflare),
            "@cf/qwen/qwen3-30b-a3b-fp8"
        )
        XCTAssertFalse(settings.isCloudflareReasoningEnabled)
    }

    func testOlderSettingsWithoutNewProviderFieldsStillDecode() throws {
        let encoded = try JSONEncoder().encode(AppSettings())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "customOpenAIBaseURL")
        object.removeValue(forKey: "cloudflareAccountID")
        object.removeValue(forKey: "cloudflareReasoningEnabled")

        let olderData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: olderData
        )

        XCTAssertEqual(decoded.configuredCustomOpenAIBaseURL, "")
        XCTAssertEqual(decoded.configuredCloudflareAccountID, "")
        XCTAssertFalse(decoded.isCloudflareReasoningEnabled)
    }

    func testCustomActionCarriesClipboardInputSetting() {
        var action = CustomAction(name: "Explain")
        action.readsClipboard = true

        XCTAssertTrue(action.usesClipboard)
        XCTAssertTrue(action.request.readsClipboard)
    }

    func testOlderCustomActionWithoutClipboardSettingStillDecodes() throws {
        let data = Data(
            """
            {
              "id": "30C79709-A25C-4B21-8A1E-32BCAB932A72",
              "name": "Explain",
              "prompt": "Explain this",
              "enabled": true,
              "providerID": "",
              "model": "",
              "inputMode": "transform",
              "inputLimit": 0,
              "outputLimit": 0
            }
            """.utf8
        )

        let action = try JSONDecoder().decode(CustomAction.self, from: data)

        XCTAssertFalse(action.usesClipboard)
        XCTAssertFalse(action.request.readsClipboard)
    }
}
