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
        for provider in Provider.allCases {
            XCTAssertFalse(provider.defaultModel.isEmpty)
        }
    }
}
