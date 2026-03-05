import AppKit

// MARK: - Ghostty Tab/Window Switching

extension AppDelegate {

    func jumpTo(_ session: ClaudeSession) {
        guard let ghostty = NSRunningApplication.runningApplications(withBundleIdentifier: "com.mitchellh.ghostty").first else { return }

        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
            ghostty.activate()
            return
        }

        let axApp = AXUIElementCreateApplication(ghostty.processIdentifier)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            ghostty.activate()
            return
        }

        let sessionCwd = getProcessCwd(pid: session.pid)
        let dirName = sessionCwd.flatMap { ($0 as NSString).lastPathComponent }

        // Strategy 1: Match window title against session's working directory name
        if let dir = dirName, !dir.isEmpty {
            for window in windows {
                let title = axTitle(of: window)
                if title.localizedCaseInsensitiveContains(dir) {
                    raiseGhosttyWindow(window, app: ghostty)
                    return
                }
            }
        }

        // Strategy 2: Search tab bar titles inside each window
        if let dir = dirName, !dir.isEmpty {
            for window in windows {
                if selectMatchingTab(in: window, matching: dir) {
                    raiseGhosttyWindow(window, app: ghostty)
                    return
                }
            }
        }

        // Strategy 3: Match by full CWD path in title
        if let cwd = sessionCwd {
            for window in windows {
                let title = axTitle(of: window)
                if title.contains(cwd) {
                    raiseGhosttyWindow(window, app: ghostty)
                    return
                }
            }
        }

        // Strategy 4: Single window — raise it, switch tab via Cmd+N
        let loginTTYs = ghosttyLoginTTYs(ghosttyPid: ghostty.processIdentifier)
        if windows.count == 1 {
            raiseGhosttyWindow(windows[0], app: ghostty)
            if let idx = loginTTYs.firstIndex(of: session.tty), idx < 9 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.pressCommandNumber(idx + 1)
                }
            }
            return
        }

        // Strategy 5: Multiple windows — correlate login process creation order
        if let ttyIdx = loginTTYs.firstIndex(of: session.tty) {
            let sortedWindows = windowsSortedByCreation(windows)
            if ttyIdx < sortedWindows.count {
                raiseGhosttyWindow(sortedWindows[ttyIdx], app: ghostty)
                return
            }
        }

        // Last resort
        ghostty.activate()
    }

    // MARK: - AX Helpers

    func axTitle(of element: AXUIElement) -> String {
        var ref: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref)
        return ref as? String ?? ""
    }

    func raiseGhosttyWindow(_ window: AXUIElement, app: NSRunningApplication) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        app.activate()
    }

    func windowsSortedByCreation(_ windows: [AXUIElement]) -> [AXUIElement] {
        struct WindowPos {
            let element: AXUIElement
            let x: CGFloat
            let y: CGFloat
        }
        var positioned: [WindowPos] = []
        for w in windows {
            var posRef: AnyObject?
            var pos = CGPoint.zero
            if AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &posRef) == .success {
                AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
            }
            positioned.append(WindowPos(element: w, x: pos.x, y: pos.y))
        }
        positioned.sort { ($0.y, $0.x) < ($1.y, $1.x) }
        return positioned.map(\.element)
    }

    func selectMatchingTab(in window: AXUIElement, matching text: String) -> Bool {
        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return false }

        for child in children {
            var roleRef: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            guard let role = roleRef as? String, role == "AXTabGroup" else { continue }

            var tabsRef: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXTabsAttribute as CFString, &tabsRef)
            guard let tabs = tabsRef as? [AXUIElement] else { continue }

            for tab in tabs {
                let tabTitle = axTitle(of: tab)
                if tabTitle.localizedCaseInsensitiveContains(text) {
                    AXUIElementPerformAction(tab, kAXPressAction as CFString)
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Process Helpers

    func getProcessCwd(pid: Int32) -> String? {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("n/") { return String(line.dropFirst()) }
        }
        return nil
    }

    func ghosttyLoginTTYs(ghosttyPid: pid_t) -> [String] {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-eo", "pid,ppid,tty,command"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var entries: [(pid: Int, tty: String)] = []
        for line in output.components(separatedBy: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[1]),
                  ppid == Int(ghosttyPid),
                  String(parts[3]).contains("/usr/bin/login") else { continue }
            entries.append((pid: pid, tty: String(parts[2])))
        }
        return entries.sorted { $0.pid < $1.pid }.map(\.tty)
    }

    func pressCommandNumber(_ number: Int) {
        let keyCodes: [Int: UInt16] = [
            1: 18, 2: 19, 3: 20, 4: 21, 5: 23,
            6: 22, 7: 26, 8: 28, 9: 25
        ]
        guard let keyCode = keyCodes[number] else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
