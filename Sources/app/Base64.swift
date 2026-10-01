// A base64 decoder, so the OG card can be a string literal in Payload.swift
// and the binary needs no Foundation.
//
// Foundation would do this in one call, but on Linux pulling Foundation into a
// statically linked binary drags in libcurl and libxml2 as shared libraries,
// which is exactly what this branch is avoiding: ./app has to run on a bare
// Debian 12 with nothing installed.
enum Base64 {
    static func decode(_ s: String) -> [UInt8] {
        var table = [Int8](repeating: -1, count: 256)
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
        for (i, c) in alphabet.enumerated() { table[Int(c)] = Int8(i) }

        var out = [UInt8]()
        out.reserveCapacity(s.utf8.count * 3 / 4)
        var acc = 0
        var bits = 0
        for c in s.utf8 {
            let v = table[Int(c)]
            if v < 0 { continue }  // padding, newlines, anything else
            acc = (acc << 6) | Int(v)
            bits += 6
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((acc >> bits) & 0xff))
            }
        }
        return out
    }
}
