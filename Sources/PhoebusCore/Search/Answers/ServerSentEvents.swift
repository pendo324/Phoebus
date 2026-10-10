import Foundation

/// One dispatched `text/event-stream` event.
public struct ServerSentEvent: Equatable, Sendable {
    public var id: String?
    /// The `event:` name; "message" when the stream gave none.
    public var event: String
    /// The `data:` lines joined with newlines.
    public var data: String

    public init(id: String? = nil, event: String = "message", data: String) {
        self.id = id
        self.event = event
        self.data = data
    }
}

/// Incremental `text/event-stream` parser. Feed it bytes in whatever chunks
/// they arrive in (a line, or a multi-byte character, may be split across
/// chunks); it returns the events completed so far. Lines end in LF, CRLF or
/// CR; `:` comment lines and `retry:` are ignored.
public struct ServerSentEventParser: Sendable {
    private var line: [UInt8] = []
    private var skipLineFeed = false
    private var id: String?
    private var event = ""
    private var data: [String] = []
    private var hasData = false

    public init() {}

    public mutating func feed<S: Sequence>(_ bytes: S) -> [ServerSentEvent] where S.Element == UInt8 {
        var events: [ServerSentEvent] = []
        for byte in bytes {
            if skipLineFeed {
                skipLineFeed = false
                if byte == 0x0A { continue }
            }
            switch byte {
            case 0x0A, 0x0D:
                skipLineFeed = byte == 0x0D
                if let dispatched = endLine() { events.append(dispatched) }
            default:
                line.append(byte)
            }
        }
        return events
    }

    /// The stream ended: a last event whose blank line never came is dropped,
    /// as the format specifies.
    public mutating func finish() -> [ServerSentEvent] {
        var events: [ServerSentEvent] = []
        if !line.isEmpty, let dispatched = endLine() { events.append(dispatched) }
        id = nil
        event = ""
        data = []
        hasData = false
        return events
    }

    private mutating func endLine() -> ServerSentEvent? {
        defer { line.removeAll(keepingCapacity: true) }
        if line.isEmpty {
            defer { event = ""; data = []; hasData = false }
            guard hasData else { return nil }
            return ServerSentEvent(id: id, event: event.isEmpty ? "message" : event, data: data.joined(separator: "\n"))
        }
        let text = String(decoding: line, as: UTF8.self)
        if text.hasPrefix(":") { return nil }
        let field: String
        var value: String
        if let colon = text.firstIndex(of: ":") {
            field = String(text[..<colon])
            value = String(text[text.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }
        } else {
            field = text
            value = ""
        }
        switch field {
        case "event": event = value
        case "data": data.append(value); hasData = true
        case "id": if !value.contains("\0") { id = value }
        default: break
        }
        return nil
    }
}
