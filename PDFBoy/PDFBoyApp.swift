// PDFBoyApp.swift
import SwiftUI

@main
struct PDFBoyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Button("Acerca de PDFBoy") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "PDFBoy",
                            .applicationVersion: "1.0",
                            .version: "1.0"
                        ]
                    )
                }
            }
        }
    }
}
