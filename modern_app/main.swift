import AppKit

private let windowAutosaveName = "JnlrMainWindow"

private func formatDate(_ date: Date?) -> String {
    guard let date else { return "" }

    struct Static {
        static let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter
        }()
    }

    return Static.formatter.string(from: date)
}

private func joinTags(_ tags: [String]?) -> String {
    guard let tags, !tags.isEmpty else { return "" }
    return tags.joined(separator: ", ")
}

private func listSubtitle(for entry: JournlerEntry) -> String {
    var parts: [String] = []

    let created = formatDate(entry.creationDate())
    if !created.isEmpty {
        parts.append(created)
    }

    let category = entry.category() ?? ""
    if !category.isEmpty {
        parts.append(category)
    }

    let tags = joinTags(entry.tags() as? [String])
    if !tags.isEmpty {
        parts.append(tags)
    }

    return parts.joined(separator: "  ·  ")
}

private func defaultJournalCandidatePaths() -> [String] {
    let manager = FileManager.default
    var paths: [String] = []

    let homeJournal = ("~/Application Documents/Journler" as NSString).expandingTildeInPath
    if manager.fileExists(atPath: homeJournal) {
        paths.append(homeJournal)
    }

    let bundlePath = Bundle.main.bundlePath as NSString
    let repoRoot = bundlePath.deletingLastPathComponent
        .split(separator: "/")
        .dropLast()
        .joined(separator: "/")
    let sampleJournal = (((repoRoot.isEmpty ? "/" : "/" + repoRoot) as NSString)
        .appendingPathComponent("../JnlrData/Journler") as NSString)
        .standardizingPath
    if manager.fileExists(atPath: sampleJournal) {
        paths.append(sampleJournal)
    }

    return paths
}

private func defaultEntrySort(_ left: JournlerEntry, _ right: JournlerEntry) -> ComparisonResult {
    let leftDate = left.creationDate()
    let rightDate = right.creationDate()

    switch (leftDate, rightDate) {
    case let (left?, right?):
        let result = right.compare(left)
        if result != .orderedSame {
            return result
        }
    case (.some, .none):
        return .orderedAscending
    case (.none, .some):
        return .orderedDescending
    case (.none, .none):
        break
    }

    return (left.title() ?? "").localizedCaseInsensitiveCompare(right.title() ?? "")
}

private func collectionSort(_ left: JournlerCollection, _ right: JournlerCollection) -> ComparisonResult {
    switch (left.indexValue(), right.indexValue()) {
    case let (left?, right?):
        let result = left.compare(right)
        if result != .orderedSame {
            return result
        }
    case (.some, .none):
        return .orderedAscending
    case (.none, .some):
        return .orderedDescending
    case (.none, .none):
        break
    }

    return (left.title() ?? "").localizedCaseInsensitiveCompare(right.title() ?? "")
}

private func sortValue(for entry: JournlerEntry, key: String) -> Any {
    switch key {
    case "title":
        return entry.title() ?? ""
    case "date":
        return entry.creationDate() ?? Date.distantPast
    case "category":
        return entry.category() ?? ""
    case "tags":
        return joinTags(entry.tags() as? [String])
    default:
        return ""
    }
}

private func compareSortValues(_ left: Any, _ right: Any) -> ComparisonResult {
    if let leftDate = left as? Date, let rightDate = right as? Date {
        return leftDate.compare(rightDate)
    }
    if let leftString = left as? String, let rightString = right as? String {
        return leftString.localizedCaseInsensitiveCompare(rightString)
    }
    if let leftNumber = left as? NSNumber, let rightNumber = right as? NSNumber {
        return leftNumber.compare(rightNumber)
    }
    return String(describing: left).localizedCaseInsensitiveCompare(String(describing: right))
}

private func runSmokeTest(_ journalPath: String) -> Int32 {
    guard let journal = JLRCompatJournal(path: (journalPath as NSString).standardizingPath) else {
        print("smoke_path=\(journalPath)")
        print("smoke_load_ok=false")
        print("smoke_error=Could not initialize compatibility journal")
        print("smoke_loaded_from_store=false")
        print("smoke_entries=0")
        return 1
    }

    let ok: Bool
    var loadError: NSError?
    do {
        try journal.load()
        ok = true
    } catch let error as NSError {
        ok = false
        loadError = error
    }

    print("smoke_path=\(journalPath)")
    print("smoke_load_ok=\(ok ? "true" : "false")")
    print("smoke_error=\(loadError?.localizedDescription ?? "<none>")")
    print("smoke_loaded_from_store=\(journal.loadedFromStore() ? "true" : "false")")
    print("smoke_entries=\(journal.entries()?.count ?? 0)")

    if ok, let entry = (journal.entries() as? [JournlerEntry])?.first {
        let content: NSAttributedString?
        var contentError: NSError?
        do {
            content = try entry.loadAttributedContent()
        } catch let error as NSError {
            content = nil
            contentError = error
        }
        print("smoke_first_title=\(entry.title() ?? "")")
        print("smoke_content_ok=\(content != nil ? "true" : "false")")
        print("smoke_content_error=\(contentError?.localizedDescription ?? "<none>")")
        print("smoke_content_length=\(content?.length ?? 0)")
    }

    return ok ? 0 : 1
}

final class SidebarNode: NSObject {
    let title: String
    let collection: JournlerCollection?
    var children: [SidebarNode] = []

    init(title: String, collection: JournlerCollection?) {
        self.title = title
        self.collection = collection
    }

    func addChild(_ child: SidebarNode) {
        children.append(child)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSTextFieldDelegate {
    private var window: NSWindow!
    private var sidebarView: NSOutlineView!
    private var tableView: NSTableView!
    private var textView: NSTextView!
    private var titleLabel: NSTextField!
    private var summaryLabel: NSTextField!
    private var metaLabel: NSTextField!
    private var statusLabel: NSTextField!

    private var journal: JLRCompatJournal?
    private var allEntries: [JournlerEntry] = []
    private var entries: [JournlerEntry] = []
    private var sidebarItems: [SidebarNode] = []
    private let initialJournalPath: String?
    private var selectedEntry: JournlerEntry?
    private var entryHasUnsavedChanges = false
    private var isRefreshingEditor = false

    init(initialJournalPath: String?) {
        self.initialJournalPath = initialJournalPath
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()

        let path = initialJournalPath ?? defaultJournalCandidatePaths().first
        if let path {
            openJournal(atPath: path)
        } else {
            statusLabel.stringValue = "No journal selected. Use File > Open Journal…"
        }

        window.makeKeyAndOrderFront(nil)
    }

    private func buildMenu() {
        let mainMenu = NSMenu(title: "MainMenu")
        NSApp.mainMenu = mainMenu

        let appItem = NSMenuItem(title: "Jnlr", action: nil, keyEquivalent: "")
        mainMenu.addItem(appItem)

        let appMenu = NSMenu(title: "Jnlr")
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Jnlr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        mainMenu.addItem(fileItem)

        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "Open Journal…", action: #selector(openJournal(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Save", action: #selector(saveDocument(_:)), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "Reload Journal", action: #selector(reloadJournal(_:)), keyEquivalent: "r")
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1200, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Jnlr"
        window.setFrameAutosaveName(windowAutosaveName)

        let contentView = window.contentView!

        let outerSplitView = NSSplitView(frame: contentView.bounds)
        outerSplitView.isVertical = true
        outerSplitView.dividerStyle = .thin
        outerSplitView.autoresizingMask = [.width, .height]
        contentView.addSubview(outerSplitView)

        let sidebarScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 220, height: outerSplitView.bounds.height))
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.autoresizingMask = [.width, .height]

        sidebarView = NSOutlineView(frame: sidebarScroll.bounds)
        let sidebarColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        sidebarColumn.title = "Collections"
        sidebarColumn.width = 200
        sidebarView.addTableColumn(sidebarColumn)
        sidebarView.outlineTableColumn = sidebarColumn
        sidebarView.headerView = nil
        sidebarView.delegate = self
        sidebarView.dataSource = self
        sidebarView.usesAlternatingRowBackgroundColors = true
        sidebarView.allowsEmptySelection = false
        sidebarView.rowHeight = 28
        sidebarScroll.documentView = sidebarView
        outerSplitView.addArrangedSubview(sidebarScroll)

        let contentSplitView = NSSplitView(frame: NSRect(x: 0, y: 0, width: 980, height: outerSplitView.bounds.height))
        contentSplitView.isVertical = true
        contentSplitView.dividerStyle = .thin
        contentSplitView.autoresizingMask = [.width, .height]
        outerSplitView.addArrangedSubview(contentSplitView)

        let tableScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 340, height: contentSplitView.bounds.height))
        tableScroll.hasVerticalScroller = true
        tableScroll.autoresizingMask = [.width, .height]

        tableView = NSTableView(frame: tableScroll.bounds)
        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleColumn.title = "Title"
        titleColumn.width = 220
        titleColumn.sortDescriptorPrototype = NSSortDescriptor(key: "title", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        tableView.addTableColumn(titleColumn)

        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.title = "Date"
        dateColumn.width = 110
        dateColumn.sortDescriptorPrototype = NSSortDescriptor(key: "date", ascending: false)
        tableView.addTableColumn(dateColumn)

        let categoryColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("category"))
        categoryColumn.title = "Category"
        categoryColumn.width = 110
        categoryColumn.sortDescriptorPrototype = NSSortDescriptor(key: "category", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        tableView.addTableColumn(categoryColumn)

        let tagsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tags"))
        tagsColumn.title = "Tags"
        tagsColumn.width = 180
        tagsColumn.sortDescriptorPrototype = NSSortDescriptor(key: "tags", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        tableView.addTableColumn(tagsColumn)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsEmptySelection = true
        tableView.rowHeight = 24
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        tableScroll.documentView = tableView
        contentSplitView.addArrangedSubview(tableScroll)

        let detailView = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: contentSplitView.bounds.height))
        detailView.autoresizingMask = [.width, .height]

        titleLabel = NSTextField(frame: NSRect(x: 20, y: detailView.bounds.height - 56, width: detailView.bounds.width - 40, height: 28))
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = true
        titleLabel.isSelectable = true
        titleLabel.font = .boldSystemFont(ofSize: 20)
        titleLabel.delegate = self
        titleLabel.autoresizingMask = [.width, .minYMargin]
        titleLabel.stringValue = "No entry selected"
        detailView.addSubview(titleLabel)

        summaryLabel = NSTextField(frame: NSRect(x: 20, y: detailView.bounds.height - 84, width: detailView.bounds.width - 40, height: 20))
        summaryLabel.isBezeled = false
        summaryLabel.drawsBackground = false
        summaryLabel.isEditable = false
        summaryLabel.isSelectable = false
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.autoresizingMask = [.width, .minYMargin]
        detailView.addSubview(summaryLabel)

        metaLabel = NSTextField(frame: NSRect(x: 20, y: detailView.bounds.height - 128, width: detailView.bounds.width - 40, height: 40))
        metaLabel.isBezeled = false
        metaLabel.drawsBackground = false
        metaLabel.isEditable = false
        metaLabel.isSelectable = false
        metaLabel.textColor = .secondaryLabelColor
        metaLabel.usesSingleLineMode = false
        metaLabel.cell?.wraps = true
        metaLabel.cell?.isScrollable = false
        metaLabel.autoresizingMask = [.width, .minYMargin]
        detailView.addSubview(metaLabel)

        statusLabel = NSTextField(frame: NSRect(x: 20, y: 12, width: detailView.bounds.width - 40, height: 36))
        statusLabel.isBezeled = false
        statusLabel.drawsBackground = false
        statusLabel.isEditable = false
        statusLabel.isSelectable = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.usesSingleLineMode = false
        statusLabel.cell?.wraps = true
        statusLabel.cell?.isScrollable = false
        statusLabel.autoresizingMask = [.width, .maxYMargin]
        detailView.addSubview(statusLabel)

        let textScroll = NSScrollView(frame: NSRect(x: 20, y: 56, width: detailView.bounds.width - 40, height: detailView.bounds.height - 196))
        textScroll.hasVerticalScroller = true
        textScroll.autoresizingMask = [.width, .height]

        textView = NSTextView(frame: textScroll.contentView.bounds)
        textView.isEditable = true
        textView.isRichText = true
        textView.importsGraphics = true
        textView.usesFindPanel = true
        textView.delegate = self
        textScroll.documentView = textView
        detailView.addSubview(textScroll)

        contentSplitView.addArrangedSubview(detailView)
        contentSplitView.adjustSubviews()
        contentSplitView.setPosition(340, ofDividerAt: 0)
        outerSplitView.adjustSubviews()
        outerSplitView.setPosition(220, ofDividerAt: 0)
    }

    private func setEntries(from journal: JLRCompatJournal) {
        let sortedEntries = (journal.entries() as? [JournlerEntry] ?? []).sorted { left, right in
            defaultEntrySort(left, right) == .orderedAscending
        }
        allEntries = sortedEntries
        entries = sortedEntries
    }

    private func rebuildSidebarItems() {
        var roots: [SidebarNode] = []
        roots.append(SidebarNode(title: "All Entries", collection: nil))

        let sortedCollections = (journal?.collections() as? [JournlerCollection] ?? []).sorted { left, right in
            collectionSort(left, right) == .orderedAscending
        }
        var nodesByTag: [NSNumber: SidebarNode] = [:]

        for collection in sortedCollections {
            let title = (collection.title()?.isEmpty == false) ? collection.title()! : "(untitled collection)"
            let node = SidebarNode(title: title, collection: collection)
            if let tagID = collection.tagID() {
                nodesByTag[tagID] = node
            }
        }

        for collection in sortedCollections {
            guard let tagID = collection.tagID(), let node = nodesByTag[tagID] else { continue }
            if let parentID = collection.parentID(), parentID.intValue >= 0, let parentNode = nodesByTag[parentID] {
                parentNode.addChild(node)
            } else {
                roots.append(node)
            }
        }

        sidebarItems = roots
    }

    private func sortedEntriesArray(from entries: [JournlerEntry]) -> [JournlerEntry] {
        let sortDescriptors = tableView.sortDescriptors
        guard !sortDescriptors.isEmpty else {
            return entries
        }

        return entries.sorted { left, right in
            for descriptor in sortDescriptors {
                let key = descriptor.key ?? ""
                let leftValue = sortValue(for: left, key: key)
                let rightValue = sortValue(for: right, key: key)
                var result = compareSortValues(leftValue, rightValue)

                if !descriptor.ascending {
                    switch result {
                    case .orderedAscending: result = .orderedDescending
                    case .orderedDescending: result = .orderedAscending
                    case .orderedSame: break
                    }
                }

                if result != .orderedSame {
                    return result == .orderedAscending
                }
            }

            return defaultEntrySort(left, right) == .orderedAscending
        }
    }

    private func currentSidebarItem() -> SidebarNode? {
        let row = sidebarView.selectedRow
        if row >= 0, let item = sidebarView.item(atRow: row) as? SidebarNode {
            return item
        }
        return sidebarItems.first
    }

    private func applySidebarSelection() {
        guard let item = currentSidebarItem() else { return }

        let visibleEntries: [JournlerEntry]
        if let collection = item.collection {
            let entryIDs = Set(((collection.entryIDs() as? [NSNumber]) ?? []).map(\.intValue))
            visibleEntries = allEntries.filter { entry in
                guard let tagID = entry.tagID() else { return false }
                return entryIDs.contains(tagID.intValue)
            }
        } else {
            visibleEntries = allEntries
        }

        entries = sortedEntriesArray(from: visibleEntries)
        tableView.reloadData()

        if !entries.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            refreshSelectedEntry()
        } else {
            titleLabel.stringValue = "No entry selected"
            summaryLabel.stringValue = ""
            metaLabel.stringValue = ""
            textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        }
    }

    private func currentSelectedEntry() -> JournlerEntry? {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count else { return nil }
        return entries[row]
    }

    private func updateStatusLabel() {
        guard let journal else {
            statusLabel.stringValue = "No journal loaded"
            statusLabel.toolTip = nil
            return
        }

        let mode = entryHasUnsavedChanges ? "Unsaved changes" : "Editable"
        let journalPath = journal.path() ?? ""
        statusLabel.stringValue = "\(mode). \(entries.count) entries, \(journal.resources().count) resources, \(journal.collections().count) collections\n\(journalPath)"
        statusLabel.toolTip = journalPath
    }

    private func markSelectedEntryDirty() {
        guard !isRefreshingEditor, currentSelectedEntry() != nil else { return }
        entryHasUnsavedChanges = true
        updateStatusLabel()
    }

    private func refreshSelectedEntry() {
        isRefreshingEditor = true
        defer {
            isRefreshingEditor = false
        }

        guard let entry = currentSelectedEntry() else {
            selectedEntry = nil
            titleLabel.stringValue = "No entry selected"
            summaryLabel.stringValue = ""
            metaLabel.stringValue = ""
            textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
            return
        }

        selectedEntry = entry
        let title = entry.title() ?? ""
        titleLabel.stringValue = title.isEmpty ? "(untitled)" : title
        summaryLabel.stringValue = listSubtitle(for: entry)

        let created = formatDate(entry.creationDate())
        let modified = formatDate(entry.modificationDate())
        let category = entry.category() ?? ""
        let tags = joinTags(entry.tags() as? [String])
        metaLabel.stringValue = "Created: \(created.isEmpty ? "-" : created)    Modified: \(modified.isEmpty ? "-" : modified)\nCategory: \(category.isEmpty ? "-" : category)    Tags: \(tags.isEmpty ? "-" : tags)    Entry ID: \(entry.tagID()?.stringValue ?? "-")"

        do {
            let content = try entry.loadAttributedContent()
            textView.textStorage?.setAttributedString(content)
        } catch let error as NSError {
            let message = "Could not load entry body.\n\n\(error.localizedDescription)"
            textView.textStorage?.setAttributedString(NSAttributedString(string: message))
        }

        entryHasUnsavedChanges = false
        updateStatusLabel()
    }

    private func promptToSaveIfNeeded() -> Bool {
        guard entryHasUnsavedChanges else { return true }

        let alert = NSAlert()
        alert.messageText = "Save changes to this entry?"
        alert.informativeText = "This writes the updated entry and JournlerStore.dict, after creating a backup copy."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            var error: NSError?
            if !saveSelectedEntry(&error) {
                let saveAlert = NSAlert()
                saveAlert.messageText = "Could not save entry"
                saveAlert.informativeText = error?.localizedDescription ?? "Unknown error"
                saveAlert.runModal()
                return false
            }
            return true
        case .alertSecondButtonReturn:
            entryHasUnsavedChanges = false
            updateStatusLabel()
            return true
        default:
            return false
        }
    }

    private func saveSelectedEntry(_ error: inout NSError?) -> Bool {
        guard let entry = currentSelectedEntry(), let journal else { return true }

        entry.setTitle(titleLabel.stringValue)
        if let copied = textView.textStorage?.copy() as? NSAttributedString {
            entry.setAttributedContent(copied)
        }

        do {
            try journal.saveEntry(entry)
        } catch let saveError as NSError {
            error = saveError
            return false
        }

        let selectedTag = entry.tagID()
        entryHasUnsavedChanges = false
        setEntries(from: journal)
        applySidebarSelection()

        if let selectedTag {
            if let row = entries.firstIndex(where: { $0.tagID() == selectedTag }) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }

        refreshSelectedEntry()
        updateStatusLabel()
        return true
    }

    @objc func saveDocument(_ sender: Any?) {
        var error: NSError?
        if !saveSelectedEntry(&error) {
            let alert = NSAlert()
            alert.messageText = "Could not save entry"
            alert.informativeText = error?.localizedDescription ?? "Unknown error"
            alert.runModal()
        }
    }

    func openJournal(atPath path: String) {
        guard promptToSaveIfNeeded() else { return }

        guard let journal = JLRCompatJournal(path: (path as NSString).standardizingPath) else {
            let alert = NSAlert()
            alert.messageText = "Could not open journal"
            alert.informativeText = "Could not initialize compatibility journal"
            alert.runModal()
            return
        }

        do {
            _ = try journal.load()
        } catch let error as NSError {
            let alert = NSAlert()
            alert.messageText = "Could not open journal"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }

        self.journal = journal
        entryHasUnsavedChanges = false

        setEntries(from: journal)
        rebuildSidebarItems()
        sidebarView.reloadData()
        sidebarView.expandItem(nil, expandChildren: true)
        sidebarView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        applySidebarSelection()
        tableView.reloadData()

        let journalTitle = journal.properties()["Title"] as? String ?? "Journal"
        window.title = "Jnlr - \(journalTitle)"
        updateStatusLabel()

        if entries.isEmpty {
            titleLabel.stringValue = "No entry selected"
            summaryLabel.stringValue = ""
            metaLabel.stringValue = ""
            textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        }
    }

    @objc func openJournal(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.urls.first {
            openJournal(atPath: url.path)
        }
    }

    @objc func reloadJournal(_ sender: Any?) {
        guard let path = journal?.path(), promptToSaveIfNeeded() else { return }
        openJournal(atPath: path)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard outlineView === sidebarView else { return 0 }
        guard let item = item as? SidebarNode else { return sidebarItems.count }
        return item.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let item = item as? SidebarNode {
            return item.children[index]
        }
        return sidebarItems[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? SidebarNode)?.children.isEmpty == false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("SidebarCell")
        let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
            let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: tableColumn?.width ?? 0, height: 24))
            let textField = NSTextField(frame: NSRect(x: 6, y: 4, width: (tableColumn?.width ?? 0) - 12, height: 18))
            textField.isBezeled = false
            textField.drawsBackground = false
            textField.isEditable = false
            textField.isSelectable = false
            textField.font = .systemFont(ofSize: 13, weight: .medium)
            cell.identifier = identifier
            cell.textField = textField
            cell.addSubview(textField)
            return cell
        }()

        guard let node = item as? SidebarNode else { return cell }
        if let collection = node.collection {
            cell.textField?.stringValue = "\(node.title) (\(collection.entryIDs()?.count ?? 0))"
        } else {
            cell.textField?.stringValue = "\(node.title) (\(allEntries.count))"
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("EntryCell-\(tableColumn.identifier.rawValue)")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
            let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: tableColumn.width, height: 22))
            let textField = NSTextField(frame: NSRect(x: 6, y: 2, width: tableColumn.width - 12, height: 18))
            textField.isBezeled = false
            textField.drawsBackground = false
            textField.isEditable = false
            textField.isSelectable = false
            if tableColumn.identifier.rawValue == "title" {
                textField.font = .systemFont(ofSize: 13, weight: .medium)
            } else {
                textField.font = .systemFont(ofSize: 12)
                textField.textColor = .secondaryLabelColor
            }
            cell.identifier = identifier
            cell.textField = textField
            cell.addSubview(textField)
            return cell
        }()

        let entry = entries[row]
        let columnIdentifier = tableColumn.identifier.rawValue
        let value: String
        switch columnIdentifier {
        case "title":
            let title = entry.title() ?? ""
            value = title.isEmpty ? "(untitled)" : title
        case "date":
            value = formatDate(entry.creationDate())
        case "category":
            value = entry.category() ?? ""
        case "tags":
            value = joinTags(entry.tags() as? [String])
        default:
            value = ""
        }

        cell.textField?.stringValue = value
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if row == self.tableView.selectedRow {
            return true
        }
        return promptToSaveIfNeeded()
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if outlineView !== sidebarView {
            return true
        }
        if let current = sidebarView.item(atRow: sidebarView.selectedRow) as? SidebarNode,
           let next = item as? SidebarNode,
           current === next {
            return true
        }
        return promptToSaveIfNeeded()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        refreshSelectedEntry()
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard tableView === self.tableView else { return }

        let selectedTag = currentSelectedEntry()?.tagID()
        applySidebarSelection()

        if let selectedTag, let row = entries.firstIndex(where: { $0.tagID() == selectedTag }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            refreshSelectedEntry()
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === sidebarView else { return }
        applySidebarSelection()
    }

    func controlTextDidChange(_ obj: Notification) {
        markSelectedEntryDirty()
    }

    func textDidChange(_ notification: Notification) {
        markSelectedEntryDirty()
    }
}

let arguments = CommandLine.arguments
if arguments.count >= 3, arguments[1] == "--smoke-test" {
    exit(runSmokeTest((arguments[2] as NSString).standardizingPath))
}

let initialPath = arguments.count >= 2 ? (arguments[1] as NSString).standardizingPath : nil
let application = NSApplication.shared
let delegate = AppDelegate(initialJournalPath: initialPath)
application.setActivationPolicy(.regular)
application.delegate = delegate
application.activate(ignoringOtherApps: true)
application.run()
