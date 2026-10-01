// swift-tools-version:6.0
import PackageDescription

// The product is called `app` because Laravel Cloud's Go runtime starts
// whatever executable the build command leaves at ./app, and that saves a
// rename in build.sh.
let package = Package(
    name: "app",
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "app",
            dependencies: [.product(name: "Hummingbird", package: "hummingbird")]
        )
    ]
)
