import Foundation

/// A minimal ZIP reader, enough for a settings backup.
///
/// Exists because this package has no zip dependency and its tests run
/// on Linux, where neither Apple's `Compression` framework nor a
/// bundled zlib is available. A settings backup is four small entries,
/// so reading the central directory and inflating them here is less
/// code than adding a dependency - and it keeps the archive checks in
/// `ApolloBackupImport` rather than split across a library boundary.
///
/// Scope is deliberately narrow: STORED and DEFLATE entries, no ZIP64,
/// no encryption, no multi-disk. An Apollo backup is all DEFLATE entries
/// with no ZIP64. Anything outside that is rejected rather than guessed at.
enum ZipReader {
    struct Entry {
        let name: String
        let compressionMethod: Int
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    enum ZipError: Error, Equatable {
        case noCentralDirectory
        case truncated
        case unsupportedCompression(Int)
        case corrupt
    }

    /// End-of-central-directory signature, and the central and local
    /// file header signatures.
    private static let endOfCentralDirectory: UInt32 = 0x0605_4b50
    private static let centralFileHeader: UInt32 = 0x0201_4b50
    private static let localFileHeader: UInt32 = 0x0403_4b50

    static func entries(in data: Data) throws -> [Entry] {
        // The EOCD record is at the end, but may be followed by a
        // variable-length comment, so it has to be searched backwards.
        // Bounded to 64KB + 22, the maximum a comment can be.
        guard data.count >= 22 else { throw ZipError.noCentralDirectory }
        let searchLimit = min(data.count, 65_536 + 22)
        var eocd: Int?
        var offset = data.count - 22
        let lowest = data.count - searchLimit
        while offset >= lowest {
            if read32(data, at: offset) == endOfCentralDirectory {
                eocd = offset
                break
            }
            offset -= 1
        }
        guard let eocd else { throw ZipError.noCentralDirectory }

        let entryCount = Int(read16(data, at: eocd + 10))
        var cursor = Int(read32(data, at: eocd + 16))
        var result: [Entry] = []
        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count,
                  read32(data, at: cursor) == centralFileHeader else {
                throw ZipError.corrupt
            }
            let method = Int(read16(data, at: cursor + 10))
            let compressed = Int(read32(data, at: cursor + 20))
            let uncompressed = Int(read32(data, at: cursor + 24))
            let nameLength = Int(read16(data, at: cursor + 28))
            let extraLength = Int(read16(data, at: cursor + 30))
            let commentLength = Int(read16(data, at: cursor + 32))
            let localOffset = Int(read32(data, at: cursor + 42))
            guard cursor + 46 + nameLength <= data.count else { throw ZipError.truncated }
            let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            let name = String(decoding: nameData, as: UTF8.self)
            result.append(Entry(name: name,
                                compressionMethod: method,
                                compressedSize: compressed,
                                uncompressedSize: uncompressed,
                                localHeaderOffset: localOffset))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return result
    }

    static func data(for entry: Entry, in data: Data) throws -> Data {
        let start = entry.localHeaderOffset
        guard start + 30 <= data.count,
              read32(data, at: start) == localFileHeader else {
            throw ZipError.corrupt
        }
        // The LOCAL header's name/extra lengths, which can differ from
        // the central directory's extra length - a classic source of
        // off-by-N in hand-rolled readers.
        let nameLength = Int(read16(data, at: start + 26))
        let extraLength = Int(read16(data, at: start + 28))
        let dataStart = start + 30 + nameLength + extraLength
        let dataEnd = dataStart + entry.compressedSize
        guard dataEnd <= data.count else { throw ZipError.truncated }
        let payload = data.subdata(in: dataStart..<dataEnd)

        switch entry.compressionMethod {
        case 0:
            guard payload.count == entry.uncompressedSize else { throw ZipError.corrupt }
            return payload
        case 8:
            // The declared size is also the limit: the archive checks cap
            // the total by what entries DECLARE, so an entry inflating
            // past its declaration would get round them.
            let output = try Inflate.run(payload, expectedSize: entry.uncompressedSize, limit: entry.uncompressedSize)
            guard output.count == entry.uncompressedSize else { throw ZipError.corrupt }
            return output
        default:
            throw ZipError.unsupportedCompression(entry.compressionMethod)
        }
    }

    private static func read16(_ data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[data.startIndex + offset]) |
            (UInt16(data[data.startIndex + offset + 1]) << 8)
    }

    private static func read32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[data.startIndex + offset]) |
            (UInt32(data[data.startIndex + offset + 1]) << 8) |
            (UInt32(data[data.startIndex + offset + 2]) << 16) |
            (UInt32(data[data.startIndex + offset + 3]) << 24)
    }
}

/// RFC 1951 DEFLATE decompression.
///
/// Written out rather than pulled in because the alternatives are a
/// package dependency or an Apple-only path (`Compression` is not
/// available on Linux, where the smoke tests run). Every Apollo backup
/// entry is DEFLATE.
enum Inflate {
    enum InflateError: Error, Equatable {
        case corrupt
        case unexpectedEnd
    }

    /// Bit reader, LSB-first as DEFLATE requires.
    private struct BitStream {
        let bytes: [UInt8]
        var bytePosition = 0
        var bitPosition = 0

        mutating func bit() throws -> Int {
            guard bytePosition < bytes.count else { throw InflateError.unexpectedEnd }
            let value = (Int(bytes[bytePosition]) >> bitPosition) & 1
            bitPosition += 1
            if bitPosition == 8 {
                bitPosition = 0
                bytePosition += 1
            }
            return value
        }

        mutating func bits(_ count: Int) throws -> Int {
            var value = 0
            for index in 0..<count {
                value |= try bit() << index
            }
            return value
        }

        mutating func alignToByte() {
            if bitPosition > 0 {
                bitPosition = 0
                bytePosition += 1
            }
        }
    }

    /// A canonical Huffman decoder, built from code lengths as the
    /// spec describes (RFC 1951 3.2.2).
    private struct Huffman {
        var counts: [Int]
        var symbols: [Int]

        init(lengths: [Int]) {
            let maxBits = 15
            counts = [Int](repeating: 0, count: maxBits + 1)
            for length in lengths where length > 0 {
                counts[length] += 1
            }
            var offsets = [Int](repeating: 0, count: maxBits + 2)
            for bits in 1...maxBits {
                offsets[bits + 1] = offsets[bits] + counts[bits]
            }
            symbols = [Int](repeating: 0, count: lengths.count)
            for (symbol, length) in lengths.enumerated() where length > 0 {
                symbols[offsets[length]] = symbol
                offsets[length] += 1
            }
        }

        func decode(_ stream: inout BitStream) throws -> Int {
            var code = 0
            var first = 0
            var index = 0
            for length in 1...15 {
                code |= try stream.bit()
                let count = counts[length]
                if code - first < count {
                    return symbols[index + (code - first)]
                }
                index += count
                first = (first + count) << 1
                code <<= 1
            }
            throw InflateError.corrupt
        }
    }

    private static let lengthBase = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
    ]
    private static let lengthExtra = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
    ]
    private static let distanceBase = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
        257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
        8193, 12289, 16385, 24577,
    ]
    private static let distanceExtra = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
        7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
    ]

    static func run(_ data: Data, expectedSize: Int, limit: Int = .max) throws -> Data {
        var stream = BitStream(bytes: [UInt8](data))
        var output: [UInt8] = []
        output.reserveCapacity(expectedSize)

        while true {
            let isFinal = try stream.bit()
            let type = try stream.bits(2)
            switch type {
            case 0:
                // Stored: align, then a length/one's-complement pair.
                stream.alignToByte()
                let length = try stream.bits(16)
                let complement = try stream.bits(16)
                guard length ^ 0xFFFF == complement else { throw InflateError.corrupt }
                guard output.count + length <= limit else { throw InflateError.corrupt }
                for _ in 0..<length {
                    output.append(UInt8(try stream.bits(8)))
                }
            case 1:
                try inflateBlock(&stream, &output,
                                 literals: fixedLiteralHuffman,
                                 distances: fixedDistanceHuffman, limit: limit)
            case 2:
                let (literals, distances) = try dynamicHuffman(&stream)
                try inflateBlock(&stream, &output, literals: literals, distances: distances, limit: limit)
            default:
                throw InflateError.corrupt
            }
            if isFinal == 1 { break }
        }
        return Data(output)
    }

    private static func inflateBlock(_ stream: inout BitStream,
                                     _ output: inout [UInt8],
                                     literals: Huffman,
                                     distances: Huffman,
                                     limit: Int) throws {
        while true {
            let symbol = try literals.decode(&stream)
            guard output.count < limit || symbol == 256 else { throw InflateError.corrupt }
            if symbol < 256 {
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let index = symbol - 257
                guard index < lengthBase.count else { throw InflateError.corrupt }
                let length = lengthBase[index] + (try stream.bits(lengthExtra[index]))
                let distanceSymbol = try distances.decode(&stream)
                guard distanceSymbol < distanceBase.count else { throw InflateError.corrupt }
                let distance = distanceBase[distanceSymbol]
                    + (try stream.bits(distanceExtra[distanceSymbol]))
                guard distance <= output.count, output.count + length <= limit else { throw InflateError.corrupt }
                // Copied byte by byte on purpose: DEFLATE allows the
                // match to overlap the output it is producing (that is
                // how runs are encoded), so a bulk copy would be wrong.
                var source = output.count - distance
                for _ in 0..<length {
                    output.append(output[source])
                    source += 1
                }
            }
        }
    }

    private static let fixedLiteralHuffman: Huffman = {
        var lengths = [Int](repeating: 8, count: 288)
        for index in 144..<256 { lengths[index] = 9 }
        for index in 256..<280 { lengths[index] = 7 }
        return Huffman(lengths: lengths)
    }()

    private static let fixedDistanceHuffman = Huffman(lengths: [Int](repeating: 5, count: 30))

    private static func dynamicHuffman(_ stream: inout BitStream) throws -> (Huffman, Huffman) {
        let literalCount = (try stream.bits(5)) + 257
        let distanceCount = (try stream.bits(5)) + 1
        let codeLengthCount = (try stream.bits(4)) + 4
        // The permuted order the spec defines for the code-length
        // alphabet (RFC 1951 3.2.7).
        let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
        var codeLengths = [Int](repeating: 0, count: 19)
        for index in 0..<codeLengthCount {
            codeLengths[order[index]] = try stream.bits(3)
        }
        let codeLengthHuffman = Huffman(lengths: codeLengths)

        var lengths: [Int] = []
        lengths.reserveCapacity(literalCount + distanceCount)
        while lengths.count < literalCount + distanceCount {
            let symbol = try codeLengthHuffman.decode(&stream)
            switch symbol {
            case 0..<16:
                lengths.append(symbol)
            case 16:
                guard let last = lengths.last else { throw InflateError.corrupt }
                let repeats = 3 + (try stream.bits(2))
                lengths.append(contentsOf: [Int](repeating: last, count: repeats))
            case 17:
                let repeats = 3 + (try stream.bits(3))
                lengths.append(contentsOf: [Int](repeating: 0, count: repeats))
            case 18:
                let repeats = 11 + (try stream.bits(7))
                lengths.append(contentsOf: [Int](repeating: 0, count: repeats))
            default:
                throw InflateError.corrupt
            }
        }
        guard lengths.count >= literalCount + distanceCount else { throw InflateError.corrupt }
        let literals = Huffman(lengths: Array(lengths[0..<literalCount]))
        let distances = Huffman(lengths: Array(lengths[literalCount..<(literalCount + distanceCount)]))
        return (literals, distances)
    }
}
