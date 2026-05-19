import Foundation
import Testing

@Suite("Analysis output schema")
struct SchemaTests {
    @Test("strict schema objects require every declared property")
    func strictRequiredKeys() throws {
        try assertStrictRequiredKeys(inResource: "analysis-output.schema.json")
        try assertStrictRequiredKeys(inResource: "analysis-patch-output.schema.json")
    }

    private func assertStrictRequiredKeys(inResource fileName: String) throws {
        let url = resourcesDirectory().appendingPathComponent(fileName)
        let data = try Data(contentsOf: url)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        try assertStrictRequiredKeys(in: object)
    }

    private func resourcesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetingRescue/Resources")
    }

    private func assertStrictRequiredKeys(in schema: [String: Any]) throws {
        if let properties = schema["properties"] as? [String: Any] {
            let required = Set(schema["required"] as? [String] ?? [])
            #expect(required == Set(properties.keys))

            for value in properties.values {
                if let child = value as? [String: Any] {
                    try assertStrictRequiredKeys(in: child)
                }
            }
        }

        if let items = schema["items"] as? [String: Any] {
            try assertStrictRequiredKeys(in: items)
        }

        for key in ["anyOf", "oneOf", "allOf"] {
            guard let variants = schema[key] as? [[String: Any]] else {
                continue
            }
            for variant in variants {
                try assertStrictRequiredKeys(in: variant)
            }
        }
    }
}
