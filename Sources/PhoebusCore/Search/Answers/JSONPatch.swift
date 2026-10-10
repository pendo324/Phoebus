import Foundation

/// RFC 6902 JSON Patch over `JSONValue`, as Reddit Answers streams its
/// document: each `patch` event is an array of operations on one growing
/// document.
public enum JSONPatch {
    public enum PatchError: Error, Equatable {
        case malformed
        case invalidPath(String)
        case testFailed(String)
    }

    public struct Operation: Equatable, Sendable {
        public var op: String
        public var path: String
        public var from: String?
        public var value: JSONValue?
    }

    /// The operations in a decoded patch array; nil when it isn't one.
    public static func operations(from value: JSONValue) -> [Operation]? {
        guard case .array(let items) = value else { return nil }
        var result: [Operation] = []
        for item in items {
            guard case .object(let object) = item, case .string(let op)? = object["op"],
                  case .string(let path)? = object["path"] else { return nil }
            var from: String?
            if case .string(let source)? = object["from"] { from = source }
            result.append(Operation(op: op, path: path, from: from, value: object["value"]))
        }
        return result
    }

    /// Applies `operations` in order. A failing operation throws and leaves
    /// the operations before it applied.
    public static func apply(_ operations: [Operation], to document: inout JSONValue) throws {
        for operation in operations {
            switch operation.op {
            case "add":
                guard let value = operation.value else { throw PatchError.malformed }
                try add(value, at: operation.path, in: &document)
            case "replace":
                guard let value = operation.value else { throw PatchError.malformed }
                try replace(value, at: operation.path, in: &document)
            case "remove":
                _ = try remove(at: operation.path, in: &document)
            case "copy":
                guard let from = operation.from else { throw PatchError.malformed }
                try add(try value(at: from, in: document), at: operation.path, in: &document)
            case "move":
                guard let from = operation.from else { throw PatchError.malformed }
                let moved = try remove(at: from, in: &document)
                try add(moved, at: operation.path, in: &document)
            case "test":
                guard let expected = operation.value else { throw PatchError.malformed }
                if try value(at: operation.path, in: document) != expected { throw PatchError.testFailed(operation.path) }
            default:
                throw PatchError.malformed
            }
        }
    }

    public static func apply(_ patch: JSONValue, to document: inout JSONValue) throws {
        guard let operations = operations(from: patch) else { throw PatchError.malformed }
        try apply(operations, to: &document)
    }

    // MARK: Pointers

    /// A JSON Pointer's reference tokens (`~1` is `/`, `~0` is `~`).
    static func tokens(_ pointer: String) throws -> [String] {
        if pointer.isEmpty { return [] }
        guard pointer.hasPrefix("/") else { throw PatchError.invalidPath(pointer) }
        return pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map {
            $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        }
    }

    public static func value(at pointer: String, in document: JSONValue) throws -> JSONValue {
        var current = document
        for token in try tokens(pointer) {
            switch current {
            case .object(let object):
                guard let next = object[token] else { throw PatchError.invalidPath(pointer) }
                current = next
            case .array(let array):
                guard let index = Int(token), array.indices.contains(index) else { throw PatchError.invalidPath(pointer) }
                current = array[index]
            default:
                throw PatchError.invalidPath(pointer)
            }
        }
        return current
    }

    // MARK: Mutations

    private static func add(_ value: JSONValue, at pointer: String, in document: inout JSONValue) throws {
        let path = try tokens(pointer)
        guard !path.isEmpty else { document = value; return }
        try withParent(of: path[...], in: &document, pointer: pointer) { parent, token in
            switch parent {
            case .object(var object):
                object[token] = value
                parent = .object(object)
            case .array(var array):
                if token == "-" {
                    array.append(value)
                } else {
                    guard let index = Int(token), index >= 0, index <= array.count else { throw PatchError.invalidPath(pointer) }
                    array.insert(value, at: index)
                }
                parent = .array(array)
            default:
                throw PatchError.invalidPath(pointer)
            }
        }
    }

    /// Replaces the value at `pointer`. Lenient where RFC 6902 refuses: a key
    /// or an index just past the end is set, since the stream rewrites parts
    /// of the document it hasn't sent yet.
    private static func replace(_ value: JSONValue, at pointer: String, in document: inout JSONValue) throws {
        let path = try tokens(pointer)
        guard !path.isEmpty else { document = value; return }
        try withParent(of: path[...], in: &document, pointer: pointer) { parent, token in
            switch parent {
            case .object(var object):
                object[token] = value
                parent = .object(object)
            case .array(var array):
                guard let index = Int(token), index >= 0, index <= array.count else { throw PatchError.invalidPath(pointer) }
                if index == array.count { array.append(value) } else { array[index] = value }
                parent = .array(array)
            default:
                throw PatchError.invalidPath(pointer)
            }
        }
    }

    private static func remove(at pointer: String, in document: inout JSONValue) throws -> JSONValue {
        let path = try tokens(pointer)
        guard !path.isEmpty else { throw PatchError.invalidPath(pointer) }
        var removed = JSONValue.null
        try withParent(of: path[...], in: &document, pointer: pointer) { parent, token in
            switch parent {
            case .object(var object):
                guard let old = object.removeValue(forKey: token) else { throw PatchError.invalidPath(pointer) }
                removed = old
                parent = .object(object)
            case .array(var array):
                guard let index = Int(token), array.indices.contains(index) else { throw PatchError.invalidPath(pointer) }
                removed = array.remove(at: index)
                parent = .array(array)
            default:
                throw PatchError.invalidPath(pointer)
            }
        }
        return removed
    }

    /// Walks to the container that holds the last token, then lets `change`
    /// edit that container with the token.
    private static func withParent(of path: ArraySlice<String>, in node: inout JSONValue, pointer: String,
                                   _ change: (inout JSONValue, String) throws -> Void) throws {
        guard let token = path.first else { throw PatchError.invalidPath(pointer) }
        if path.count == 1 {
            try change(&node, token)
            return
        }
        switch node {
        case .object(var object):
            guard var child = object[token] else { throw PatchError.invalidPath(pointer) }
            let original = child
            do {
                try withParent(of: path.dropFirst(), in: &child, pointer: pointer, change)
            } catch {
                object[token] = original
                throw error
            }
            object[token] = child
            node = .object(object)
        case .array(var array):
            guard let index = Int(token), array.indices.contains(index) else { throw PatchError.invalidPath(pointer) }
            var child = array[index]
            let original = child
            do {
                try withParent(of: path.dropFirst(), in: &child, pointer: pointer, change)
            } catch {
                array[index] = original
                throw error
            }
            array[index] = child
            node = .array(array)
        default:
            throw PatchError.invalidPath(pointer)
        }
    }
}
