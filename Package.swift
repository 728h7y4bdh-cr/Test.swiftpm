// swift-tools-version: 5.9

// Swift Playgrounds上でビルドするiOSアプリのパッケージ定義。
// AppleProductTypesの.iOSApplicationにより、Xcodeを使わずにアプリを構成する
// （要件定義書「開発環境」：Swift Playground(Xcodeは使わない)）。

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Test",
    // 要件定義書「開発環境」：iPad / iPhone 実機での動作が前提のため、iOS 17以上を対象とする
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Test",
            targets: ["AppModule"],
            bundleIdentifier: "com.example.Test",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .box),
            accentColor: .presetColor(.blue),
            // 要件定義書「開発環境」：iPad / iPhone の両方で動作させるため両デバイスファミリを指定
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeLeft,
                .landscapeRight
            ],
            // 要件定義書 2章「使用するライブラリ」：Bluetooth通信（Core Bluetooth）を使用するため、
            // NSBluetoothAlwaysUsageDescriptionに相当する許可理由文言を設定する。
            // PS設計書 0.1「通信ライブラリ」：通信にはCore Bluetoothを使用する方針に対応。
            // なお、Wi-Fi関連のUsageDescription/Capabilityは意図的に一切追加していない
            // （要件定義書 2章「Wifi機能は常時OFFにすること」に対応）。
            capabilities: [
                .bluetoothAlways(purposeString: "Bluetooth通信でデータの送受信を行うために使用します。")
            ]
        )
    ],
    targets: [
        // アプリ本体のソースコードは Sources/ 配下（AppModuleターゲット）にまとめている
        .executableTarget(
            name: "AppModule",
            path: "Sources"
        )
    ]
)
