import Foundation

/// A `multipart/form-data` body: text fields, then one file.
public struct MultipartForm: Sendable {
    public struct File: Sendable {
        public let fieldName: String
        public let filename: String
        public let mimeType: String
        public let data: Data

        public init(fieldName: String, filename: String, mimeType: String, data: Data) {
            self.fieldName = fieldName
            self.filename = filename
            self.mimeType = mimeType
            self.data = data
        }
    }

    public let boundary: String
    public let body: Data
    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public init(fields: [(name: String, value: String)], file: File, boundary: String = "Phoebus-\(UUID().uuidString)") {
        self.boundary = boundary
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        for field in fields {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(Self.quoted(field.name))\"\r\n\r\n\(field.value)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(Self.quoted(file.fieldName))\"; filename=\"\(Self.quoted(file.filename))\"\r\nContent-Type: \(file.mimeType)\r\n\r\n")
        body.append(file.data)
        append("\r\n--\(boundary)--\r\n")
        self.body = body
    }

    private static func quoted(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
