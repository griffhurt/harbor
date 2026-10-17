import AppKit
import HarborKit

// Build-time helper: `HarborStub --render-icon <out.icns> <symbol> <hex> <folder|tile>`
let arguments = CommandLine.arguments
if arguments.count == 6, arguments[1] == "--render-icon" {
    let data = IconRenderer.icnsData(symbol: arguments[3], hex: arguments[4], style: IconStyle(rawValue: arguments[5]) ?? .tile)
    do {
        try data.write(to: URL(fileURLWithPath: arguments[2]))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = StubDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
