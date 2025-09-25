import Foundation

struct SHA256Hasher {
    private static let initialState: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    private var h: [UInt32] = initialState
    private var processedBytes: UInt64 = 0
    private var buffer = Data()

    mutating func update(data: Data) {
        processedBytes += UInt64(data.count)
        buffer.append(data)
        while buffer.count >= 64 {
            let chunk = buffer.prefix(64)
            process(chunk: chunk)
            buffer.removeFirst(64)
        }
    }

    mutating func finalize() -> [UInt8] {
        var finalBuffer = buffer
        finalBuffer.append(0x80)
        while (finalBuffer.count % 64) != 56 {
            finalBuffer.append(0)
        }
        let bitLength = processedBytes * 8
        let lengthBytes = withUnsafeBytes(of: bitLength.bigEndian) { Data($0) }
        finalBuffer.append(contentsOf: lengthBytes)
        while finalBuffer.count >= 64 {
            let chunk = finalBuffer.prefix(64)
            process(chunk: chunk)
            finalBuffer.removeFirst(64)
        }
        var digest: [UInt8] = []
        for value in h {
            digest.append(contentsOf: withUnsafeBytes(of: value.bigEndian, Array.init))
        }
        buffer.removeAll(keepingCapacity: false)
        h = Self.initialState
        processedBytes = 0
        return digest
    }

    private mutating func process(chunk: Data.SubSequence) {
        var w = [UInt32](repeating: 0, count: 64)
        chunk.withUnsafeBytes { ptr in
            for i in 0..<16 {
                let start = i * 4
                let value = ptr[start..<start+4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                w[i] = value
            }
        }
        for i in 16..<64 {
            let s0 = rotateRight(w[i-15], by: 7) ^ rotateRight(w[i-15], by: 18) ^ (w[i-15] >> 3)
            let s1 = rotateRight(w[i-2], by: 17) ^ rotateRight(w[i-2], by: 19) ^ (w[i-2] >> 10)
            w[i] = w[i-16] &+ s0 &+ w[i-7] &+ s1
        }

        var a = h[0]
        var b = h[1]
        var c = h[2]
        var d = h[3]
        var e = h[4]
        var f = h[5]
        var g = h[6]
        var hh = h[7]

        for i in 0..<64 {
            let s1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
            let ch = (e & f) ^ ((~e) & g)
            let temp1 = hh &+ s1 &+ ch &+ Self.k[i] &+ w[i]
            let s0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = s0 &+ maj

            hh = g
            g = f
            f = e
            e = d &+ temp1
            d = c
            c = b
            b = a
            a = temp1 &+ temp2
        }

        h[0] = h[0] &+ a
        h[1] = h[1] &+ b
        h[2] = h[2] &+ c
        h[3] = h[3] &+ d
        h[4] = h[4] &+ e
        h[5] = h[5] &+ f
        h[6] = h[6] &+ g
        h[7] = h[7] &+ hh
    }

    private func rotateRight(_ value: UInt32, by: UInt32) -> UInt32 {
        (value >> by) | (value << (32 - by))
    }
}
