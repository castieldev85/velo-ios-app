// swift-tools-version:5.9
// Velo iOS — pacchetto locale con libsignal (fork monocles pq-omemo-2) e la cifratura OMEMO2 PQ.
// SignalFfi.xcframework e Sources/LibSignalClient vengono messi qui dalla CI
// (workflow build-libsignal-ios.yml); in git ci sono solo i sorgenti Velo.
// SPDX-License-Identifier: AGPL-3.0-only

import PackageDescription
import Foundation

let hasLibSignal = FileManager.default.fileExists(
    atPath: Context.packageDirectory + "/SignalFfi.xcframework")

var targets: [Target] = [
    .target(name: "VeloPQCrypto"),
    .testTarget(name: "VeloPQCryptoTests", dependencies: ["VeloPQCrypto"]),
]
var products: [Product] = [
    .library(name: "VeloPQCrypto", targets: ["VeloPQCrypto"]),
]
if hasLibSignal {
    targets += [
        .binaryTarget(name: "SignalFfi", path: "SignalFfi.xcframework"),
        .target(name: "LibSignalClient", dependencies: ["SignalFfi"],
                swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]),
        .target(name: "VeloPQ", dependencies: ["LibSignalClient", "VeloPQCrypto"],
                linkerSettings: [.linkedLibrary("c++")]),   // BoringSSL dentro libsignal e' C++
    ]
    // Dinamica: libsignal (Rust) ha simboli con gli stessi nomi della libsignal-protocol-c di Monal
    // (signal_message_*) e un secondo runtime Rust; in un'immagine separata non si scontrano.
    products.append(.library(name: "VeloPQ", type: .dynamic, targets: ["VeloPQ"]))
}

let package = Package(
    name: "VeloSignal",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: products,
    targets: targets
)
