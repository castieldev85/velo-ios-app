// Velo iOS — KMAC256 (NIST SP 800-185) su Keccak-f[1600], per la Velo OMEMO2 PQ.
// Stesso algoritmo della Velo Android (BouncyCastle KMAC), verificato con i vettori NIST
// e con quelli della proto-XEP OMEMO-PQXDH (vedi Tests/VeloPQCryptoTests).
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

enum Keccak {
    private static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
        0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
        0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]
    private static let rotations: [UInt64] = [
        1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44,
    ]
    private static let piLane: [Int] = [
        10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1,
    ]

    @inline(__always) private static func rotl(_ x: UInt64, _ n: UInt64) -> UInt64 {
        return (x << n) | (x >> (64 - n))
    }

    static func permute(_ st: inout [UInt64]) {
        var bc = [UInt64](repeating: 0, count: 5)
        for round in 0..<24 {
            for i in 0..<5 {
                bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20]
            }
            for i in 0..<5 {
                let t = bc[(i + 4) % 5] ^ rotl(bc[(i + 1) % 5], 1)
                for j in stride(from: 0, to: 25, by: 5) {
                    st[j + i] ^= t
                }
            }
            var t = st[1]
            for i in 0..<24 {
                let j = piLane[i]
                let tmp = st[j]
                st[j] = rotl(t, rotations[i])
                t = tmp
            }
            for j in stride(from: 0, to: 25, by: 5) {
                for i in 0..<5 { bc[i] = st[j + i] }
                for i in 0..<5 {
                    st[j + i] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5]
                }
            }
            st[0] ^= roundConstants[round]
        }
    }

    /// Sponge Keccak[c] con `rate` byte di rate, byte di dominio `domain` (0x04 per cSHAKE,
    /// 0x1F per SHAKE, 0x06 per SHA3), uscita di `outputLength` byte.
    static func sponge(rate: Int, domain: UInt8, input: [UInt8], outputLength: Int) -> [UInt8] {
        var st = [UInt64](repeating: 0, count: 25)
        var offset = 0
        func absorbBlock(_ block: ArraySlice<UInt8>) {
            var i = 0
            for b in block {
                st[i / 8] ^= UInt64(b) << UInt64((i % 8) * 8)
                i += 1
            }
        }
        while input.count - offset >= rate {
            absorbBlock(input[offset..<(offset + rate)])
            permute(&st)
            offset += rate
        }
        var last = [UInt8](input[offset...])
        last.append(domain)
        while last.count < rate { last.append(0) }
        last[rate - 1] ^= 0x80
        absorbBlock(last[0...])
        permute(&st)
        var out = [UInt8]()
        out.reserveCapacity(outputLength)
        while true {
            for i in 0..<rate {
                if out.count == outputLength { return out }
                out.append(UInt8(truncatingIfNeeded: st[i / 8] >> UInt64((i % 8) * 8)))
            }
            permute(&st)
        }
    }
}

public enum Kmac {
    private static let rate256 = 136

    static func leftEncode(_ x: UInt64) -> [UInt8] {
        var bytes = [UInt8]()
        var v = x
        repeat {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        } while v > 0
        return [UInt8(bytes.count)] + bytes
    }

    static func rightEncode(_ x: UInt64) -> [UInt8] {
        var bytes = [UInt8]()
        var v = x
        repeat {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        } while v > 0
        return bytes + [UInt8(bytes.count)]
    }

    static func encodeString(_ s: [UInt8]) -> [UInt8] {
        return leftEncode(UInt64(s.count) * 8) + s
    }

    static func bytepad(_ x: [UInt8], _ w: Int) -> [UInt8] {
        var z = leftEncode(UInt64(w)) + x
        while z.count % w != 0 { z.append(0) }
        return z
    }

    static func cshake256(_ x: [UInt8], outputLength: Int, functionName: [UInt8], customization: [UInt8]) -> [UInt8] {
        if functionName.isEmpty && customization.isEmpty {
            return Keccak.sponge(rate: rate256, domain: 0x1F, input: x, outputLength: outputLength)
        }
        let prefix = bytepad(encodeString(functionName) + encodeString(customization), rate256)
        return Keccak.sponge(rate: rate256, domain: 0x04, input: prefix + x, outputLength: outputLength)
    }

    /// KMAC256(K, X, L = 8 * outputLength, S) — NIST SP 800-185 §4.
    public static func kmac256(key: [UInt8], data: [UInt8], customization: [UInt8], outputLength: Int) -> [UInt8] {
        let newX = bytepad(encodeString(key), rate256) + data + rightEncode(UInt64(outputLength) * 8)
        return cshake256(newX, outputLength: outputLength, functionName: Array("KMAC".utf8), customization: customization)
    }

    /// SHA3-512, usato solo nei test per i vettori della proto-XEP.
    public static func sha3_512(_ input: [UInt8]) -> [UInt8] {
        return Keccak.sponge(rate: 72, domain: 0x06, input: input, outputLength: 64)
    }
}
