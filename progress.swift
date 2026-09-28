// AutoSub progress window: a small floating panel that follows the helper's
// status file ("state|percent|message") and offers a Cancel button.
// Usage: autosub-progress <status-file> <pid-file> <title>
import AppKit

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write("usage: autosub-progress <status> <pidfile> <title>\n".data(using: .utf8)!)
    exit(2)
}
let statusPath = args[1], pidPath = args[2], movieTitle = args[3]

final class Controller: NSObject {
    let panel: NSPanel
    let titleLabel = NSTextField(labelWithString: "")
    let stageLabel = NSTextField(labelWithString: "Starting…")
    let bar = NSProgressIndicator()
    let button = NSButton(title: "Cancel", target: nil, action: nil)
    var stage = ""
    var stageStart = Date()
    var finished = false

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 104),
                        styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .hudWindow],
                        backing: .buffered, defer: false)
        super.init()
        panel.title = "AutoSub"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true

        titleLabel.stringValue = movieTitle
        titleLabel.font = .boldSystemFont(ofSize: 12)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        stageLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        stageLabel.textColor = .secondaryLabelColor
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 100
        button.target = self
        button.action = #selector(buttonPressed)
        button.bezelStyle = .rounded
        button.controlSize = .small

        let bottom = NSStackView(views: [stageLabel, NSView(), button])
        let stack = NSStackView(views: [titleLabel, bar, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        for v in [titleLabel, bar, bottom] {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
        }
        panel.contentView = stack

        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 400, y: screen.maxY - 124))
        }
        panel.orderFrontRegardless()

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    func poll() {
        guard !finished,
              let raw = try? String(contentsOfFile: statusPath, encoding: .utf8) else { return }
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return }
        let (state, pct, msg) = (parts[0], Double(parts[1]) ?? 0, parts[2])

        switch state {
        case "running":
            if msg != stage { stage = msg; stageStart = Date() }
            bar.doubleValue = pct
            stageLabel.stringValue = "\(msg)… \(Int(pct))%" + eta(pct)
        case "done":
            finish(text: "Subtitles ready ✓", closeAfter: 4)
        case "cancelled":
            finish(text: "Cancelled", closeAfter: 1.5)
        case "error":
            finish(text: "Error: \(msg)", closeAfter: nil)
        default:
            break
        }
    }

    func eta(_ pct: Double) -> String {
        let elapsed = Date().timeIntervalSince(stageStart)
        guard pct >= 2, elapsed > 5 else { return "" }
        let left = Int(elapsed * (100 - pct) / pct)
        return left >= 60 ? "  ·  ~\(left / 60) min left" : "  ·  ~\(left)s left"
    }

    func finish(text: String, closeAfter: TimeInterval?) {
        finished = true
        bar.doubleValue = text.hasPrefix("Subtitles") ? 100 : bar.doubleValue
        stageLabel.stringValue = text
        button.title = "Close"
        if let delay = closeAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { NSApp.terminate(nil) }
        }
    }

    @objc func buttonPressed() {
        if finished { NSApp.terminate(nil); return }
        if let s = try? String(contentsOfFile: pidPath, encoding: .utf8),
           let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            kill(pid, SIGTERM)
        }
        stageLabel.stringValue = "Cancelling…"
        button.isEnabled = false
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
app.run()
