import Cocoa
import WebKit
import EventKit
import UserNotifications
import Security

final class LifeDashboardDelegate: NSObject,
                                   NSApplicationDelegate,
                                   WKScriptMessageHandler,
                                   WKNavigationDelegate,
                                   WKUIDelegate,
                                   UNUserNotificationCenterDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!

    private let musicBundleIdentifier = "com.apple.Music"
    private let eventStore = EKEventStore()

    private var lastArtworkTrackKey = ""
    private var lastArtworkDataURL = ""
    private var backupTimer: Timer?
    private var updateTimer: Timer?

    private let nativeVersion = "0.15.0"
    private let bundledDashboardVersion = "0.20.0"

    private let updateFeedKey = "LifeDashboardUpdateFeedURL"
    private let autoUpdateKey = "LifeDashboardAutoUpdates"
    private let dashboardVersionKey = "LifeDashboardDashboardVersion"
    private let previousDashboardVersionKey = "LifeDashboardPreviousDashboardVersion"
    private let previousDashboardPathKey = "LifeDashboardPreviousDashboardPath"
    private let previousResourceBackupsKey = "LifeDashboardPreviousResourceBackups"
    private let nativeDownloadURLKey = "LifeDashboardNativeDownloadURL"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        UserDefaults.standard.register(defaults: [
            autoUpdateKey: true,
            updateFeedKey: "https://raw.githubusercontent.com/gnf25n4tpk-pixel/life-dashboard-updates/main/update.json"
        ])

        let storedDashboardVersion =
            UserDefaults.standard.string(forKey: dashboardVersionKey) ?? "0.0.0"

        if compareVersions(bundledDashboardVersion, storedDashboardVersion) == .orderedDescending {
            UserDefaults.standard.set(bundledDashboardVersion, forKey: dashboardVersionKey)
        }

        buildMainMenu()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let controller = WKUserContentController()
        ["music", "files", "calendar", "print", "notifications", "updates", "nutritionImport"].forEach {
            controller.add(self, name: $0)
        }
        configuration.userContentController = controller

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self

        let frame = NSRect(x: 0, y: 0, width: 1380, height: 900)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Life Dashboard"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 980, height: 680)
        window.center()
        window.contentView = webView
        window.setFrameAutosaveName("LifeDashboardMainWindow")

        UNUserNotificationCenter.current().delegate = self

        guard let htmlURL = Bundle.main.url(forResource: "dashboard", withExtension: "html"),
              let resourceURL = Bundle.main.resourceURL else {
            showFatal("dashboard.html wurde im App-Bundle nicht gefunden.")
            return
        }

        webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceURL)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        performAutoBackup(timestamped: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.pushMusicState()
            self?.pushNotificationState()
            self?.syncCalendar(requestIfNeeded: false)
            self?.startAutoBackupTimer()
            self?.startUpdateTimer()
            self?.pushUpdateState(status: "idle", message: nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self?.checkForUpdates(manual: false)
            }
        }
    }

    // MARK: - Menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Über Life Dashboard", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Einstellungen", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Life Dashboard beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "Ablage")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "Backup erstellen", action: #selector(createBackupFromMenu), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "Backup laden", action: #selector(loadBackupFromMenu), keyEquivalent: "o")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Ernährungsplan drucken", action: #selector(printNutritionFromMenu), keyEquivalent: "p")

        let navigateMenuItem = NSMenuItem()
        mainMenu.addItem(navigateMenuItem)
        let navigateMenu = NSMenu(title: "Navigation")
        navigateMenuItem.submenu = navigateMenu
        addNavigateItem(to: navigateMenu, title: "Startseite", key: "1", target: "home")
        addNavigateItem(to: navigateMenu, title: "Finanzen", key: "2", target: "finanzen")
        addNavigateItem(to: navigateMenu, title: "Gym", key: "3", target: "gym")
        addNavigateItem(to: navigateMenu, title: "Ernährung", key: "4", target: "ernaehrung")
        addNavigateItem(to: navigateMenu, title: "Kalender", key: "5", target: "kalender")

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "Darstellung")
        viewMenuItem.submenu = viewMenu

        let darkModeItem = NSMenuItem(
            title: "Dark Mode umschalten",
            action: #selector(toggleDarkModeFromMenu),
            keyEquivalent: "d"
        )
        darkModeItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(darkModeItem)

        let backupMenuItem = NSMenuItem()
        mainMenu.addItem(backupMenuItem)
        let backupMenu = NSMenu(title: "Backup")
        backupMenuItem.submenu = backupMenu
        backupMenu.addItem(withTitle: "Automatisches Backup jetzt erstellen", action: #selector(runAutoBackupNow), keyEquivalent: "b")

        let updateMenuItem = NSMenuItem()
        mainMenu.addItem(updateMenuItem)
        let updateMenu = NSMenu(title: "Updates")
        updateMenuItem.submenu = updateMenu
        updateMenu.addItem(withTitle: "Nach Updates suchen", action: #selector(checkUpdatesFromMenu), keyEquivalent: "u")
        updateMenu.addItem(withTitle: "Letztes Dashboard-Update zurücksetzen", action: #selector(rollbackUpdateFromMenu), keyEquivalent: "")

        NSApp.mainMenu = mainMenu
    }

    private func addNavigateItem(to menu: NSMenu, title: String, key: String, target: String) {
        let item = NSMenuItem(title: title, action: #selector(handleNavigateMenuItem(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = [.command]
        item.representedObject = target
        menu.addItem(item)
    }

    @objc private func handleNavigateMenuItem(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? String else { return }
        runJavaScript("desktopNavigate('\(target)');")
    }

    @objc private func createBackupFromMenu() {
        runJavaScript("desktopCreateBackup();")
    }

    @objc private func loadBackupFromMenu() {
        runJavaScript("desktopLoadBackup();")
    }

    @objc private func printNutritionFromMenu() {
        runJavaScript("desktopPrintNutritionPlan();")
    }

    @objc private func toggleDarkModeFromMenu() {
        runJavaScript("desktopToggleDarkMode();")
    }

    @objc private func runAutoBackupNow() {
        performAutoBackup(timestamped: true)
        showAlert("Automatisches Backup erstellt.", detail: autoBackupDirectory().path)
    }

    @objc private func checkUpdatesFromMenu() {
        checkForUpdates(manual: true)
    }

    @objc private func rollbackUpdateFromMenu() {
        rollbackLastDashboardUpdate()
    }


    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Life Dashboard"
        alert.informativeText = "Desktop-Version mit Backup, Kalender, Gym, Ernährung und Apple Music."
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func openSettings() {
        openSystemSettings(urls: [
            "x-apple.systempreferences:",
            "x-apple.systempreferences:com.apple.settings.General"
        ])
    }

    // MARK: - JavaScript dialogs

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Life Dashboard"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in
            completionHandler()
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Life Dashboard"
        alert.informativeText = message
        alert.addButton(withTitle: "Bestätigen")
        alert.addButton(withTitle: "Abbrechen")
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    // MARK: - Bridge

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }

        switch message.name {
        case "music":
            handleMusic(action: action)
        case "files":
            handleFiles(action: action, body: body)
        case "calendar":
            handleCalendar(action: action)
        case "print":
            printDashboard()
        case "notifications":
            handleNotifications(action: action, body: body)
        case "updates":
            handleUpdates(action: action, body: body)
        case "nutritionImport":
            guard message.frameInfo.isMainFrame,
                  message.frameInfo.request.url?.isFileURL == true else { return }
            handleNutritionImport(action: action, body: body)
        default:
            break
        }
    }

    // MARK: - Nutrition import

    private func handleNutritionImport(action: String, body: [String: Any]) {
        switch action {
        case "copyPrompt":
            guard let prompt = body["text"] as? String,
                  !prompt.isEmpty, prompt.count <= 25_000 else {
                sendJSONObject(function: "window.nativeNutritionPromptCopyResult",
                               object: ["ok": false])
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let copied = pasteboard.setString(prompt, forType: .string)
            sendJSONObject(function: "window.nativeNutritionPromptCopyResult",
                           object: ["ok": copied])

        case "openChatGPT":
            if let url = URL(string: "https://chatgpt.com/") {
                NSWorkspace.shared.open(url)
            }

        case "deleteLegacyKey":
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.lifedashboard.desktop.openai",
                kSecAttrAccount as String: "nutrition-plan"
            ]
            let status = SecItemDelete(query as CFDictionary)
            let removed = status == errSecSuccess || status == errSecItemNotFound
            if removed {
                UserDefaults.standard.removeObject(forKey: "LifeDashboardOpenAIKeyConfigured")
            }
            sendJSONObject(function: "window.nativeLegacyKeyRemovalResult", object: [
                "ok": removed,
                "message": removed ? "Bisheriger API-Schlüssel entfernt."
                    : "Schlüsselbund konnte den bisherigen Schlüssel nicht entfernen (\(status))."
            ])

        default:
            break
        }
    }

    // MARK: - Files / Backup

    private func handleFiles(action: String, body: [String: Any]) {
        switch action {
        case "saveBackup":
            let panel = NSSavePanel()
            panel.title = "Life Dashboard Backup speichern"
            panel.nameFieldStringValue =
                body["filename"] as? String ?? "Life-Dashboard-Backup.json"
            panel.allowedFileTypes = ["json"]
            panel.canCreateDirectories = true

            guard panel.runModal() == .OK,
                  let url = panel.url,
                  let text = body["text"] as? String else {
                return
            }

            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                showAlert("Backup konnte nicht gespeichert werden.", detail: error.localizedDescription)
            }

        case "openBackup":
            let panel = NSOpenPanel()
            panel.title = "Life Dashboard Backup laden"
            panel.allowedFileTypes = ["json"]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true

            guard panel.runModal() == .OK,
                  let url = panel.url else {
                return
            }

            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                sendJSONObject(function: "window.nativeBackupLoaded", object: ["text": text])
            } catch {
                showAlert("Backup konnte nicht geladen werden.", detail: error.localizedDescription)
            }

        default:
            break
        }
    }

    private func startAutoBackupTimer() {
        backupTimer?.invalidate()
        backupTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.performAutoBackup(timestamped: false)
        }
    }

    private func autoBackupDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Life Dashboard/Auto-Backups", isDirectory: true)
    }

    private func performAutoBackup(timestamped: Bool) {
        runJavaScript("buildLifeDashboardBackupText();") { [weak self] result in
            guard let self = self else { return }
            guard let text = result as? String, !text.isEmpty else { return }

            let directory = self.autoBackupDirectory()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let latestURL = directory.appendingPathComponent("Latest.json")
            try? text.write(to: latestURL, atomically: true, encoding: .utf8)

            if timestamped {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "de_DE")
                formatter.dateFormat = "yyyy-MM-dd_HH-mm"
                let stamp = formatter.string(from: Date())
                let archiveURL = directory.appendingPathComponent("Life-Dashboard-Auto-Backup-\(stamp).json")
                try? text.write(to: archiveURL, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Printing

    private func printDashboard() {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.orientation = .landscape
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic

        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }

    // MARK: - Calendar / EventKit

    private func handleCalendar(action: String) {
        switch action {
        case "sync":
            syncCalendar(requestIfNeeded: true)
        case "state":
            syncCalendar(requestIfNeeded: false)
        case "settings":
            openSystemSettings(
                urls: [
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
                    "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars"
                ]
            )
        default:
            break
        }
    }

    private func syncCalendar(requestIfNeeded: Bool) {
        let status = EKEventStore.authorizationStatus(for: .event)

        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess:
                pushCalendarEvents()
            case .notDetermined:
                guard requestIfNeeded else {
                    pushCalendarStatus("notDetermined")
                    return
                }

                eventStore.requestFullAccessToEvents { [weak self] granted, error in
                    DispatchQueue.main.async {
                        if granted {
                            self?.pushCalendarEvents()
                        } else {
                            self?.pushCalendarStatus("denied", error: error?.localizedDescription)
                        }
                    }
                }
            case .denied:
                pushCalendarStatus("denied")
            case .restricted, .writeOnly:
                pushCalendarStatus("restricted")
            @unknown default:
                pushCalendarStatus("restricted")
            }
        } else {
            switch status {
            case .authorized:
                pushCalendarEvents()
            case .notDetermined:
                guard requestIfNeeded else {
                    pushCalendarStatus("notDetermined")
                    return
                }
                eventStore.requestAccess(to: .event) { [weak self] granted, error in
                    DispatchQueue.main.async {
                        if granted {
                            self?.pushCalendarEvents()
                        } else {
                            self?.pushCalendarStatus("denied", error: error?.localizedDescription)
                        }
                    }
                }
            case .denied:
                pushCalendarStatus("denied")
            case .restricted:
                pushCalendarStatus("restricted")
            @unknown default:
                pushCalendarStatus("restricted")
            }
        }
    }

    private func pushCalendarEvents() {
        let calendar = Calendar.current
        let now = Date()
        guard let start = calendar.date(byAdding: .month, value: -12, to: now),
              let end = calendar.date(byAdding: .month, value: 36, to: now) else {
            pushCalendarStatus("granted")
            return
        }

        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "de_DE")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "de_DE")
        timeFormatter.timeZone = .current
        timeFormatter.dateFormat = "HH:mm"

        let events: [[String: Any]] = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                let identifier = (event.eventIdentifier ?? UUID().uuidString) + "-" + String(Int(event.startDate.timeIntervalSince1970))
                return [
                    "id": "apple-native-" + identifier,
                    "title": event.title ?? "Kalender",
                    "date": dateFormatter.string(from: event.startDate),
                    "time": event.isAllDay ? "" : timeFormatter.string(from: event.startDate),
                    "allDay": event.isAllDay,
                    "location": event.location ?? "",
                    "calendarName": event.calendar.title,
                    "sourceFile": "native-macos-calendar"
                ]
            }

        sendJSONObject(function: "window.nativeCalendarState", object: [
            "status": "granted",
            "events": events
        ])
    }

    private func pushCalendarStatus(_ status: String, error: String? = nil) {
        var payload: [String: Any] = ["status": status]
        if let error = error {
            payload["error"] = error
        }
        sendJSONObject(function: "window.nativeCalendarState", object: payload)
    }

    // MARK: - Notifications

    private func handleNotifications(action: String, body: [String: Any]) {
        switch action {
        case "state":
            pushNotificationState()
        case "request":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
                self?.pushNotificationState()
            }
        case "settings":
            openSystemSettings(
                urls: [
                    "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
                    "x-apple.systempreferences:com.apple.preference.notifications"
                ]
            )
        case "notify":
            let content = UNMutableNotificationContent()
            content.title = body["title"] as? String ?? "Life Dashboard"
            content.body = body["body"] as? String ?? ""
            content.sound = .default

            let identifier = body["identifier"] as? String ?? UUID().uuidString
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        default:
            break
        }
    }

    private func pushNotificationState() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status: String
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                status = "authorized"
            case .denied:
                status = "denied"
            case .notDetermined:
                status = "notDetermined"
            @unknown default:
                status = "notDetermined"
            }

            self?.sendJSONObject(function: "window.nativeNotificationState", object: ["status": status])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Music

    private func handleMusic(action: String) {
        switch action {
        case "open":
            openMusic()
        case "playPause":
            runMusicCommand("playpause")
        case "next":
            runMusicCommand("next track")
        case "previous":
            runMusicCommand("previous track")
        case "state":
            pushMusicState()
        default:
            break
        }
    }

    private var isMusicRunning: Bool {
        return !NSRunningApplication.runningApplications(withBundleIdentifier: musicBundleIdentifier).isEmpty
    }

    private func openMusic() {
        guard let musicURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: musicBundleIdentifier) else {
            pushMusicState(error: "Die Music-App wurde nicht gefunden.")
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: musicURL, configuration: config) { [weak self] _, error in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if let error = error {
                    self?.pushMusicState(error: error.localizedDescription)
                } else {
                    self?.pushMusicState()
                }
            }
        }
    }

    private func runMusicCommand(_ command: String) {
        if !isMusicRunning {
            openMusic()
            return
        }

        let source = """
        tell application "Music"
            \(command)
        end tell
        """

        var scriptError: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&scriptError)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            if let scriptError = scriptError {
                let message = scriptError[NSAppleScript.errorMessage] as? String ?? "Music konnte nicht gesteuert werden."
                self?.pushMusicState(error: message)
            } else {
                self?.pushMusicState()
            }
        }
    }

    private func pushMusicState(error explicitError: String? = nil) {
        var state: [String: Any] = [
            "available": NSWorkspace.shared.urlForApplication(withBundleIdentifier: musicBundleIdentifier) != nil,
            "running": isMusicRunning,
            "isPlaying": false,
            "title": "",
            "artist": "",
            "album": "",
            "artworkDataUrl": "",
            "error": explicitError ?? ""
        ]

        guard isMusicRunning else {
            sendMusicState(state)
            return
        }

        let source = """
        tell application "Music"
            set dashboardState to (player state as text)
            set dashboardTitle to ""
            set dashboardArtist to ""
            set dashboardAlbum to ""

            try
                set dashboardTitle to name of current track
                set dashboardArtist to artist of current track
                set dashboardAlbum to album of current track
            end try

            return dashboardState & linefeed & dashboardTitle & linefeed & dashboardArtist & linefeed & dashboardAlbum
        end tell
        """

        var scriptError: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&scriptError)

        if let raw = result?.stringValue {
            let parts = raw.components(separatedBy: "\n")
            if let first = parts.first {
                state["isPlaying"] = first.lowercased().contains("playing")
            }
            if parts.count > 1 { state["title"] = parts[1] }
            if parts.count > 2 { state["artist"] = parts[2] }
            if parts.count > 3 { state["album"] = parts[3] }
        }

        let trackKey = "\(state["title"] ?? "")|\(state["artist"] ?? "")|\(state["album"] ?? "")"
        if trackKey != lastArtworkTrackKey {
            lastArtworkTrackKey = trackKey
            lastArtworkDataURL = fetchMusicArtworkDataURL()
        }
        state["artworkDataUrl"] = lastArtworkDataURL

        if explicitError == nil,
           let scriptError = scriptError,
           let message = scriptError[NSAppleScript.errorMessage] as? String,
           !message.isEmpty {
            state["error"] = message
        }

        sendMusicState(state)
    }

    private func fetchMusicArtworkDataURL() -> String {
        let source = """
        tell application "Music"
            try
                return data of artwork 1 of current track
            on error
                return missing value
            end try
        end tell
        """

        var scriptError: NSDictionary?
        guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&scriptError) else {
            return ""
        }

        let rawData = descriptor.data
        guard !rawData.isEmpty,
              let image = NSImage(data: rawData),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return ""
        }

        return "data:image/png;base64," + png.base64EncodedString()
    }

    private func sendMusicState(_ state: [String: Any]) {
        sendJSONObject(function: "window.nativeMusicState", object: state)
    }


    // MARK: - Updates

    private struct ResourceUpdate: Decodable {
        let kind: String
        let url: String
        let target: String?
        let sha256: String
        let encoding: String?
    }

    private struct ResourcePayload {
        let spec: ResourceUpdate
        let data: Data
    }

    private struct ResourceBackupRecord: Codable {
        let originalPath: String
        let backupPath: String?
        let existed: Bool
    }

    private struct UpdateManifest: Decodable {
        let dashboardVersion: String
        let minimumNativeVersion: String?
        let dashboardURL: String?
        let dashboardParts: [String]?
        let dashboardGzipBase64URL: String?
        let sha256: String
        let resources: [ResourceUpdate]?
        let releaseNotes: String?
        let nativeDownloadURL: String?
    }

    private func handleUpdates(action: String, body: [String: Any]) {
        switch action {
        case "state":
            pushUpdateState(status: "idle", message: nil)

        case "setFeed":
            let value = (body["feedUrl"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(value, forKey: updateFeedKey)
            pushUpdateState(
                status: "idle",
                message: value.isEmpty
                    ? "Update-Quelle noch nicht eingerichtet"
                    : "Update-Quelle gespeichert"
            )

        case "setAuto":
            let enabled = body["enabled"] as? Bool ?? true
            UserDefaults.standard.set(enabled, forKey: autoUpdateKey)
            pushUpdateState(
                status: "idle",
                message: enabled
                    ? "Automatische Updates aktiv"
                    : "Automatische Updates deaktiviert"
            )

        case "check":
            checkForUpdates(manual: true)

        case "rollback":
            rollbackLastDashboardUpdate()

        case "openNativeUpdate":
            guard let raw = UserDefaults.standard.string(forKey: nativeDownloadURLKey),
                  let url = URL(string: raw) else {
                return
            }
            NSWorkspace.shared.open(url)

        default:
            break
        }
    }

    private func startUpdateTimer() {
        updateTimer?.invalidate()

        updateTimer = Timer.scheduledTimer(
            withTimeInterval: 6 * 60 * 60,
            repeats: true
        ) { [weak self] _ in
            self?.checkForUpdates(manual: false)
        }
    }

    private func checkForUpdates(manual: Bool) {
        let feed = UserDefaults.standard
            .string(forKey: updateFeedKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let autoUpdate = UserDefaults.standard.bool(forKey: autoUpdateKey)

        guard !feed.isEmpty else {
            if manual {
                pushUpdateState(
                    status: "noFeed",
                    message: "Update-Quelle noch nicht eingerichtet"
                )
            } else {
                pushUpdateState(status: "idle", message: nil)
            }
            return
        }

        guard let manifestURL = URL(string: feed) else {
            pushUpdateState(
                status: "error",
                message: "Ungültige Update-URL"
            )
            return
        }

        pushUpdateState(status: "checking", message: "Suche nach Updates …")

        fetchData(from: manifestURL) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                self.pushUpdateState(
                    status: "error",
                    message: "Update-Prüfung fehlgeschlagen: \(error.localizedDescription)"
                )

            case .success(let data):
                do {
                    let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)

                    if let minimum = manifest.minimumNativeVersion,
                       self.compareVersions(minimum, self.nativeVersion) == .orderedDescending {
                        if let nativeURL = manifest.nativeDownloadURL {
                            UserDefaults.standard.set(nativeURL, forKey: self.nativeDownloadURLKey)
                        }

                        self.pushUpdateState(
                            status: "nativeRequired",
                            message: "Neue Desktop-Basis erforderlich"
                        )
                        return
                    }

                    let current =
                        UserDefaults.standard.string(forKey: self.dashboardVersionKey)
                        ?? self.bundledDashboardVersion

                    guard self.compareVersions(manifest.dashboardVersion, current) == .orderedDescending else {
                        self.pushUpdateState(
                            status: "current",
                            message: "Aktuell · Dashboard \(current)"
                        )
                        return
                    }

                    if !manual && !autoUpdate {
                        self.pushUpdateState(
                            status: "available",
                            message: "Update \(manifest.dashboardVersion) verfügbar"
                        )
                        return
                    }

                    self.installDashboardUpdate(
                        manifest: manifest,
                        manifestURL: manifestURL
                    )
                } catch {
                    self.pushUpdateState(
                        status: "error",
                        message: "Update-Datei ist ungültig"
                    )
                }
            }
        }
    }

    private func installDashboardUpdate(
        manifest: UpdateManifest,
        manifestURL: URL
    ) {
        pushUpdateState(
            status: "downloading",
            message: "Installiere Update \(manifest.dashboardVersion) …"
        )

        if let compressed = manifest.dashboardGzipBase64URL,
           !compressed.isEmpty {
            guard let payloadURL = URL(
                string: compressed,
                relativeTo: manifestURL
            )?.absoluteURL else {
                pushUpdateState(status: "error", message: "Update-Datei nicht gefunden")
                return
            }

            fetchData(from: payloadURL) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .failure(let error):
                    self.pushUpdateState(
                        status: "error",
                        message: "Download fehlgeschlagen: \(error.localizedDescription)"
                    )

                case .success(let encodedData):
                    do {
                        let dashboardData = try self.decodeGzipBase64(encodedData)
                        self.verifyDashboardAndFetchResources(
                            data: dashboardData,
                            manifest: manifest,
                            manifestURL: manifestURL
                        )
                    } catch {
                        self.pushUpdateState(
                            status: "error",
                            message: "Dashboard-Update konnte nicht entpackt werden"
                        )
                    }
                }
            }
            return
        }

        if let parts = manifest.dashboardParts, !parts.isEmpty {
            fetchDashboardParts(parts, relativeTo: manifestURL) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .failure(let error):
                    self.pushUpdateState(
                        status: "error",
                        message: "Download fehlgeschlagen: \(error.localizedDescription)"
                    )
                case .success(let data):
                    self.verifyDashboardAndFetchResources(
                        data: data,
                        manifest: manifest,
                        manifestURL: manifestURL
                    )
                }
            }
            return
        }

        guard let rawURL = manifest.dashboardURL,
              let payloadURL = URL(string: rawURL, relativeTo: manifestURL)?.absoluteURL else {
            pushUpdateState(status: "error", message: "Update-Datei nicht gefunden")
            return
        }

        fetchData(from: payloadURL) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                self.pushUpdateState(
                    status: "error",
                    message: "Download fehlgeschlagen: \(error.localizedDescription)"
                )
            case .success(let data):
                self.verifyDashboardAndFetchResources(
                    data: data,
                    manifest: manifest,
                    manifestURL: manifestURL
                )
            }
        }
    }

    private func decodeGzipBase64(_ encodedData: Data) throws -> Data {
        guard let text = String(data: encodedData, encoding: .utf8) else {
            throw NSError(domain: "LifeDashboardUpdates", code: 10)
        }

        let cleaned = text.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let compressed = Data(base64Encoded: cleaned) else {
            throw NSError(domain: "LifeDashboardUpdates", code: 11)
        }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("life-dashboard-\(UUID().uuidString).html.gz")
        try compressed.write(to: temp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temp) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc", temp.path]
        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe

        try process.run()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0, !result.isEmpty else {
            throw NSError(domain: "LifeDashboardUpdates", code: 12)
        }

        return result
    }

    private func fetchDashboardParts(
        _ parts: [String],
        relativeTo manifestURL: URL,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        var combined = Data()

        func fetchPart(at index: Int) {
            if index >= parts.count {
                completion(.success(combined))
                return
            }

            guard let partURL = URL(string: parts[index], relativeTo: manifestURL)?.absoluteURL else {
                completion(.failure(NSError(
                    domain: "LifeDashboardUpdates",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Ungültige Update-Datei"]
                )))
                return
            }

            fetchData(from: partURL) { result in
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let data):
                    combined.append(data)
                    fetchPart(at: index + 1)
                }
            }
        }

        fetchPart(at: 0)
    }

    private func verifyDashboardAndFetchResources(
        data: Data,
        manifest: UpdateManifest,
        manifestURL: URL
    ) {
        let actualHash = sha256(data: data)
        let expectedHash = manifest.sha256.lowercased()

        guard !expectedHash.isEmpty, actualHash == expectedHash else {
            pushUpdateState(status: "error", message: "Update-Prüfsumme stimmt nicht")
            return
        }

        fetchResourcePayloads(
            manifest.resources ?? [],
            relativeTo: manifestURL
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                self.pushUpdateState(
                    status: "error",
                    message: "App-Ressource konnte nicht geladen werden: \(error.localizedDescription)"
                )
            case .success(let resources):
                self.replaceDashboardHTML(
                    data: data,
                    newVersion: manifest.dashboardVersion,
                    resources: resources
                )
            }
        }
    }

    private func fetchResourcePayloads(
        _ resources: [ResourceUpdate],
        relativeTo manifestURL: URL,
        completion: @escaping (Result<[ResourcePayload], Error>) -> Void
    ) {
        if resources.isEmpty {
            completion(.success([]))
            return
        }

        var results: [ResourcePayload] = []

        func fetchNext(_ index: Int) {
            if index >= resources.count {
                completion(.success(results))
                return
            }

            let spec = resources[index]
            guard let url = URL(string: spec.url, relativeTo: manifestURL)?.absoluteURL else {
                completion(.failure(NSError(
                    domain: "LifeDashboardUpdates",
                    code: 20,
                    userInfo: [NSLocalizedDescriptionKey: "Ungültige Ressourcen-URL"]
                )))
                return
            }

            fetchData(from: url) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .failure(let error):
                    completion(.failure(error))

                case .success(let rawData):
                    let decoded: Data
                    if (spec.encoding ?? "raw").lowercased() == "base64" {
                        guard let string = String(data: rawData, encoding: .utf8),
                              let data = Data(base64Encoded:
                                string.components(separatedBy: .whitespacesAndNewlines).joined()) else {
                            completion(.failure(NSError(
                                domain: "LifeDashboardUpdates",
                                code: 21,
                                userInfo: [NSLocalizedDescriptionKey: "Ressource ist nicht gültig"]
                            )))
                            return
                        }
                        decoded = data
                    } else {
                        decoded = rawData
                    }

                    guard self.sha256(data: decoded) == spec.sha256.lowercased() else {
                        completion(.failure(NSError(
                            domain: "LifeDashboardUpdates",
                            code: 22,
                            userInfo: [NSLocalizedDescriptionKey: "Ressourcen-Prüfsumme stimmt nicht"]
                        )))
                        return
                    }

                    results.append(ResourcePayload(spec: spec, data: decoded))
                    fetchNext(index + 1)
                }
            }
        }

        fetchNext(0)
    }

    private func replaceDashboardHTML(
        data: Data,
        newVersion: String,
        resources: [ResourcePayload]
    ) {
        guard let dashboardURL = Bundle.main.url(forResource: "dashboard", withExtension: "html") else {
            pushUpdateState(status: "error", message: "Dashboard-Datei fehlt")
            return
        }

        let currentVersion =
            UserDefaults.standard.string(forKey: dashboardVersionKey)
            ?? bundledDashboardVersion

        let backupDirectory = updateBackupDirectory()
        var resourceBackups: [ResourceBackupRecord] = []

        do {
            try FileManager.default.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: true
            )

            let safeVersion = currentVersion.replacingOccurrences(of: "/", with: "-")
            let dashboardBackupURL = backupDirectory
                .appendingPathComponent("dashboard-\(safeVersion).html")

            if FileManager.default.fileExists(atPath: dashboardBackupURL.path) {
                try? FileManager.default.removeItem(at: dashboardBackupURL)
            }
            try FileManager.default.copyItem(at: dashboardURL, to: dashboardBackupURL)

            UserDefaults.standard.set(currentVersion, forKey: previousDashboardVersionKey)
            UserDefaults.standard.set(dashboardBackupURL.path, forKey: previousDashboardPathKey)

            for (index, payload) in resources.enumerated() {
                let originalURL = try resourceTargetURL(for: payload.spec)
                let existed = FileManager.default.fileExists(atPath: originalURL.path)
                var backupPath: String? = nil

                if existed {
                    let backup = backupDirectory.appendingPathComponent(
                        "resource-\(safeVersion)-\(index)-\(originalURL.lastPathComponent)"
                    )
                    try? FileManager.default.removeItem(at: backup)
                    try FileManager.default.copyItem(at: originalURL, to: backup)
                    backupPath = backup.path
                }

                resourceBackups.append(ResourceBackupRecord(
                    originalPath: originalURL.path,
                    backupPath: backupPath,
                    existed: existed
                ))
            }

            if let encoded = try? JSONEncoder().encode(resourceBackups) {
                UserDefaults.standard.set(encoded, forKey: previousResourceBackupsKey)
            }

            try data.write(to: dashboardURL, options: .atomic)

            for payload in resources {
                try installResource(payload)
            }

            guard resignOwnBundle() else {
                throw NSError(
                    domain: "LifeDashboardUpdates",
                    code: 30,
                    userInfo: [NSLocalizedDescriptionKey: "App konnte nicht signiert werden"]
                )
            }

            UserDefaults.standard.set(newVersion, forKey: dashboardVersionKey)

            pushUpdateState(
                status: "installed",
                message: "Update \(newVersion) installiert"
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.reloadDashboard()
            }
        } catch {
            try? restoreFile(
                original: dashboardURL,
                backupPath: UserDefaults.standard.string(forKey: previousDashboardPathKey),
                existed: true
            )

            for record in resourceBackups {
                try? restoreFile(
                    original: URL(fileURLWithPath: record.originalPath),
                    backupPath: record.backupPath,
                    existed: record.existed
                )
            }

            _ = resignOwnBundle()
            pushUpdateState(status: "error", message: "Update konnte nicht installiert werden")
        }
    }

    private func resourceTargetURL(for spec: ResourceUpdate) throws -> URL {
        switch spec.kind {
        case "appIconPNG":
            guard let resources = Bundle.main.resourceURL else {
                throw NSError(domain: "LifeDashboardUpdates", code: 31)
            }
            return resources.appendingPathComponent("AppIcon.icns")

        case "bundleResource":
            guard let target = spec.target,
                  target.hasPrefix("Contents/Resources/"),
                  !target.contains("..") else {
                throw NSError(domain: "LifeDashboardUpdates", code: 32)
            }
            return Bundle.main.bundleURL.appendingPathComponent(target)

        default:
            throw NSError(domain: "LifeDashboardUpdates", code: 33)
        }
    }

    private func installResource(_ payload: ResourcePayload) throws {
        let target = try resourceTargetURL(for: payload.spec)

        switch payload.spec.kind {
        case "appIconPNG":
            try buildICNS(fromPNGData: payload.data, outputURL: target)
            if let image = NSImage(data: payload.data) {
                NSApp.applicationIconImage = image
            }
            NSWorkspace.shared.noteFileSystemChanged(Bundle.main.bundlePath)

        case "bundleResource":
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try payload.data.write(to: target, options: .atomic)

        default:
            throw NSError(domain: "LifeDashboardUpdates", code: 34)
        }
    }

    private func buildICNS(fromPNGData data: Data, outputURL: URL) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("life-dashboard-icon-\(UUID().uuidString)", isDirectory: true)
        let iconset = root.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        let source = root.appendingPathComponent("icon.png")

        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        try data.write(to: source, options: .atomic)
        defer { try? FileManager.default.removeItem(at: root) }

        let variants: [(Int, String)] = [
            (16, "icon_16x16.png"),
            (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"),
            (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"),
            (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"),
            (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"),
            (1024, "icon_512x512@2x.png")
        ]

        for (size, name) in variants {
            try runProcess(
                "/usr/bin/sips",
                arguments: [
                    "-z", String(size), String(size),
                    source.path,
                    "--out", iconset.appendingPathComponent(name).path
                ]
            )
        }

        try? FileManager.default.removeItem(at: outputURL)
        try runProcess(
            "/usr/bin/iconutil",
            arguments: ["-c", "icns", iconset.path, "-o", outputURL.path]
        )
    }

    private func runProcess(_ path: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "LifeDashboardUpdates", code: 35)
        }
    }

    private func restoreFile(
        original: URL,
        backupPath: String?,
        existed: Bool
    ) throws {
        if existed, let backupPath = backupPath {
            try? FileManager.default.removeItem(at: original)
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: backupPath),
                to: original
            )
        } else {
            try? FileManager.default.removeItem(at: original)
        }
    }

    private func rollbackLastDashboardUpdate() {
        guard let backupPath = UserDefaults.standard.string(forKey: previousDashboardPathKey),
              let previousVersion = UserDefaults.standard.string(forKey: previousDashboardVersionKey),
              FileManager.default.fileExists(atPath: backupPath),
              let dashboardURL = Bundle.main.url(forResource: "dashboard", withExtension: "html") else {
            pushUpdateState(status: "error", message: "Kein vorheriges Update vorhanden")
            return
        }

        do {
            try? FileManager.default.removeItem(at: dashboardURL)
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: backupPath),
                to: dashboardURL
            )

            if let stored = UserDefaults.standard.data(forKey: previousResourceBackupsKey),
               let records = try? JSONDecoder().decode([ResourceBackupRecord].self, from: stored) {
                for record in records {
                    try restoreFile(
                        original: URL(fileURLWithPath: record.originalPath),
                        backupPath: record.backupPath,
                        existed: record.existed
                    )
                }
            }

            guard resignOwnBundle() else {
                pushUpdateState(status: "error", message: "Rollback konnte nicht signiert werden")
                return
            }

            UserDefaults.standard.set(previousVersion, forKey: dashboardVersionKey)
            UserDefaults.standard.removeObject(forKey: previousDashboardPathKey)
            UserDefaults.standard.removeObject(forKey: previousDashboardVersionKey)
            UserDefaults.standard.removeObject(forKey: previousResourceBackupsKey)

            NSWorkspace.shared.noteFileSystemChanged(Bundle.main.bundlePath)
            pushUpdateState(status: "installed", message: "Zurück auf Version \(previousVersion)")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.reloadDashboard()
            }
        } catch {
            pushUpdateState(status: "error", message: "Rollback fehlgeschlagen")
        }
    }

    private func reloadDashboard() {
        guard let htmlURL =
                Bundle.main.url(forResource: "dashboard", withExtension: "html"),
              let resourceURL = Bundle.main.resourceURL else {
            return
        }

        webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceURL)
    }

    private func updateBackupDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return base
            .appendingPathComponent("Life Dashboard", isDirectory: true)
            .appendingPathComponent("Update Backups", isDirectory: true)
    }

    private func resignOwnBundle() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = [
            "--force",
            "--deep",
            "--sign",
            "-",
            Bundle.main.bundlePath
        ]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func sha256(data: Data) -> String {
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempURL = tempDirectory
            .appendingPathComponent("life-dashboard-update-\(UUID().uuidString)")

        do {
            try data.write(to: tempURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
            process.arguments = ["-a", "256", tempURL.path]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return ""
            }

            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: output, encoding: .utf8) ?? ""
            return text.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        } catch {
            return ""
        }
    }

    private func fetchData(
        from url: URL,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        if url.isFileURL {
            do {
                completion(.success(try Data(contentsOf: url)))
            } catch {
                completion(.failure(error))
            }
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(
                    domain: "LifeDashboardUpdates",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Keine Update-Daten empfangen"
                    ]
                )))
                return
            }

            completion(.success(data))
        }.resume()
    }

    private func compareVersions(
        _ lhs: String,
        _ rhs: String
    ) -> ComparisonResult {
        let left = lhs
            .split(separator: ".")
            .map { Int($0) ?? 0 }

        let right = rhs
            .split(separator: ".")
            .map { Int($0) ?? 0 }

        let length = max(left.count, right.count)

        for index in 0..<length {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0

            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }

        return .orderedSame
    }

    private func pushUpdateState(
        status: String,
        message: String?
    ) {
        let feed =
            UserDefaults.standard.string(forKey: updateFeedKey) ?? ""

        let dashboardVersion =
            UserDefaults.standard.string(forKey: dashboardVersionKey)
            ?? bundledDashboardVersion

        let autoUpdate =
            UserDefaults.standard.bool(forKey: autoUpdateKey)

        let nativeDownloadURL =
            UserDefaults.standard.string(forKey: nativeDownloadURLKey) ?? ""

        let fallbackMessage: String
        if feed.isEmpty {
            fallbackMessage = "Update-Quelle noch nicht eingerichtet"
        } else {
            fallbackMessage =
                "Desktop \(nativeVersion) · Dashboard \(dashboardVersion)"
        }

        sendJSONObject(
            function: "window.nativeUpdateState",
            object: [
                "nativeVersion": nativeVersion,
                "dashboardVersion": dashboardVersion,
                "feedUrl": feed,
                "autoUpdate": autoUpdate,
                "status": status,
                "message": message ?? fallbackMessage,
                "nativeDownloadUrl": nativeDownloadURL
            ]
        )
    }

    // MARK: - Helpers

    private func runJavaScript(_ code: String, completion: ((Any?) -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(code) { result, _ in
                completion?(result)
            }
        }
    }

    private func sendJSONObject(function: String, object: Any) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else {
            return
        }

        runJavaScript("\(function)(\(json));")
    }

    private func openSystemSettings(urls: [String]) {
        for raw in urls {
            if let url = URL(string: raw),
               NSWorkspace.shared.open(url) {
                return
            }
        }

        let settingsURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.open(settingsURL)
    }

    private func showAlert(_ message: String, detail: String = "") {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showFatal(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Life Dashboard"
        alert.informativeText = text
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let dashboardDelegate = LifeDashboardDelegate()
app.delegate = dashboardDelegate
app.run()
