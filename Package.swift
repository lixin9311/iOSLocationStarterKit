// swift-tools-version:5.6
import PackageDescription

let packageName = "LocationStarterKit"  // <-- Change this to yours
let package = Package(
  name: "",
  defaultLocalization: "en",
  platforms: [
    .iOS(.v15)
  ],
  products: [
    .library(name: packageName, targets: [packageName])
  ],
  targets: [
    .target(
      name: packageName,
      path: packageName
    )
  ]
)
