#import <Cocoa/Cocoa.h>

#import "../compat/probe_model.h"

static NSString *JLRWindowAutosaveName = @"JnlrMainWindow";

@interface JLRSidebarNode : NSObject
{
    NSString *_title;
    JournlerCollection *_collection;
    NSMutableArray *_children;
}

- (instancetype)initWithTitle:(NSString *)title collection:(JournlerCollection *)collection;
- (void)addChild:(JLRSidebarNode *)child;
- (NSString *)title;
- (JournlerCollection *)collection;
- (NSArray *)children;
@end

@interface JLRAppDelegate : NSObject <NSApplicationDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSTextFieldDelegate>
{
    NSWindow *_window;
    NSOutlineView *_sidebarView;
    NSTableView *_tableView;
    NSTextView *_textView;
    NSTextField *_titleLabel;
    NSTextField *_summaryLabel;
    NSTextField *_metaLabel;
    NSTextField *_statusLabel;
    JLRCompatJournal *_journal;
    NSArray *_allEntries;
    NSArray *_entries;
    NSArray *_sidebarItems;
    NSString *_initialJournalPath;
    JournlerEntry *_selectedEntry;
    BOOL _entryHasUnsavedChanges;
    BOOL _isRefreshingEditor;
}

- (instancetype)initWithInitialJournalPath:(NSString *)path;
- (void)openJournalAtPath:(NSString *)path;
- (void)openJournal:(id)sender;
- (void)reloadJournal:(id)sender;
- (void)saveDocument:(id)sender;
- (BOOL)saveSelectedEntry:(NSError **)error;
- (BOOL)promptToSaveIfNeeded;
- (void)updateStatusLabel;
- (void)markSelectedEntryDirty;
- (void)rebuildSidebarItems;
- (void)applySidebarSelection;
- (NSArray *)sortedEntriesArrayFromArray:(NSArray *)entries;
- (void)refreshSelectedEntry;
@end

static NSString *JLRFormatDate(NSDate *date)
{
    if (date == nil) {
        return @"";
    }

    static NSDateFormatter *formatter = nil;
    if (formatter == nil) {
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateStyle:NSDateFormatterMediumStyle];
        [formatter setTimeStyle:NSDateFormatterNoStyle];
    }
    return [formatter stringFromDate:date];
}

static NSString *JLRJoinTags(NSArray *tags)
{
    if (![tags isKindOfClass:[NSArray class]] || [tags count] == 0) {
        return @"";
    }
    return [tags componentsJoinedByString:@", "];
}

static NSString *JLRListSubtitleForEntry(JournlerEntry *entry)
{
    NSMutableArray *parts = [NSMutableArray array];
    NSString *date = JLRFormatDate([entry creationDate]);
    if ([date length] > 0) {
        [parts addObject:date];
    }

    NSString *category = [entry category];
    if ([category length] > 0) {
        [parts addObject:category];
    }

    NSString *tags = JLRJoinTags([entry tags]);
    if ([tags length] > 0) {
        [parts addObject:tags];
    }

    return [parts componentsJoinedByString:@"  ·  "];
}

static NSArray *JLRDefaultJournalCandidatePaths(void)
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSMutableArray *paths = [NSMutableArray array];

    NSString *homeJournal = [@"~/Application Documents/Journler" stringByExpandingTildeInPath];
    if ([manager fileExistsAtPath:homeJournal]) {
        [paths addObject:homeJournal];
    }

    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *repoRoot = [[[bundlePath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByStandardizingPath];
    NSString *sampleJournal = [[repoRoot stringByAppendingPathComponent:@"../JnlrData/Journler"] stringByStandardizingPath];
    if ([manager fileExistsAtPath:sampleJournal]) {
        [paths addObject:sampleJournal];
    }

    return paths;
}

static NSInteger JLREntrySort(id leftEntry, id rightEntry, void *context)
{
    NSDate *leftDate = [leftEntry creationDate];
    NSDate *rightDate = [rightEntry creationDate];

    if (leftDate != nil && rightDate != nil) {
        NSComparisonResult dateResult = [rightDate compare:leftDate];
        if (dateResult != NSOrderedSame) {
            return dateResult;
        }
    } else if (leftDate != nil) {
        return NSOrderedAscending;
    } else if (rightDate != nil) {
        return NSOrderedDescending;
    }

    NSString *leftTitle = [leftEntry title] ?: @"";
    NSString *rightTitle = [rightEntry title] ?: @"";
    return [leftTitle localizedCaseInsensitiveCompare:rightTitle];
}

static NSInteger JLRCollectionSort(id leftCollection, id rightCollection, void *context)
{
    NSNumber *leftIndex = [leftCollection indexValue];
    NSNumber *rightIndex = [rightCollection indexValue];

    if (leftIndex != nil && rightIndex != nil) {
        NSComparisonResult indexResult = [leftIndex compare:rightIndex];
        if (indexResult != NSOrderedSame) {
            return indexResult;
        }
    } else if (leftIndex != nil) {
        return NSOrderedAscending;
    } else if (rightIndex != nil) {
        return NSOrderedDescending;
    }

    NSString *leftTitle = [leftCollection title] ?: @"";
    NSString *rightTitle = [rightCollection title] ?: @"";
    return [leftTitle localizedCaseInsensitiveCompare:rightTitle];
}

static id JLRSortValueForEntry(JournlerEntry *entry, NSString *key)
{
    if ([key isEqualToString:@"title"]) {
        return [entry title] ?: @"";
    }
    if ([key isEqualToString:@"date"]) {
        return [entry creationDate] ?: [NSDate distantPast];
    }
    if ([key isEqualToString:@"category"]) {
        return [entry category] ?: @"";
    }
    if ([key isEqualToString:@"tags"]) {
        return JLRJoinTags([entry tags]) ?: @"";
    }
    return @"";
}

static int JLRRunSmokeTest(NSString *journalPath)
{
    JLRCompatJournal *journal = [[JLRCompatJournal alloc] initWithPath:journalPath];
    NSError *error = nil;
    BOOL ok = [journal load:&error];

    printf("smoke_path=%s\n", [journalPath UTF8String]);
    printf("smoke_load_ok=%s\n", ok ? "true" : "false");
    printf("smoke_error=%s\n", error ? [[[error localizedDescription] description] UTF8String] : "<none>");
    printf("smoke_loaded_from_store=%s\n", [journal loadedFromStore] ? "true" : "false");
    printf("smoke_entries=%lu\n", (unsigned long)[[journal entries] count]);

    if (ok && [[journal entries] count] > 0) {
        JournlerEntry *entry = [[journal entries] objectAtIndex:0];
        NSError *contentError = nil;
        NSAttributedString *content = [entry loadAttributedContent:&contentError];
        printf("smoke_first_title=%s\n", [[[entry title] description] UTF8String]);
        printf("smoke_content_ok=%s\n", content ? "true" : "false");
        printf("smoke_content_error=%s\n",
               contentError ? [[[contentError localizedDescription] description] UTF8String] : "<none>");
        printf("smoke_content_length=%lu\n", (unsigned long)[content length]);
    }

    [journal release];
    return ok ? 0 : 1;
}

@implementation JLRSidebarNode

- (instancetype)initWithTitle:(NSString *)title collection:(JournlerCollection *)collection
{
    self = [super init];
    if (self) {
        _title = [title copy];
        _collection = [collection retain];
        _children = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_title release];
    [_collection release];
    [_children release];
    [super dealloc];
}

- (void)addChild:(JLRSidebarNode *)child
{
    [_children addObject:child];
}

- (NSString *)title { return _title; }
- (JournlerCollection *)collection { return _collection; }
- (NSArray *)children { return _children; }

@end

@implementation JLRAppDelegate

- (instancetype)initWithInitialJournalPath:(NSString *)path
{
    self = [super init];
    if (self) {
        _initialJournalPath = [path copy];
        _allEntries = [[NSArray alloc] init];
        _entries = [[NSArray alloc] init];
        _sidebarItems = [[NSArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_window release];
    [_sidebarView release];
    [_tableView release];
    [_textView release];
    [_titleLabel release];
    [_summaryLabel release];
    [_metaLabel release];
    [_statusLabel release];
    [_journal release];
    [_allEntries release];
    [_entries release];
    [_sidebarItems release];
    [_initialJournalPath release];
    [super dealloc];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [self buildMenu];
    [self buildWindow];

    NSString *path = _initialJournalPath;
    if (path == nil) {
        NSArray *candidates = JLRDefaultJournalCandidatePaths();
        path = [candidates count] > 0 ? [candidates objectAtIndex:0] : nil;
    }

    if (path != nil) {
        [self openJournalAtPath:path];
    } else {
        [_statusLabel setStringValue:@"No journal selected. Use File > Open Journal…"];
    }

    [_window makeKeyAndOrderFront:nil];
}

- (void)buildMenu
{
    NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle:@"MainMenu"] autorelease];
    [NSApp setMainMenu:mainMenu];

    NSMenuItem *appItem = [[[NSMenuItem alloc] initWithTitle:@"Jnlr" action:NULL keyEquivalent:@""] autorelease];
    [mainMenu addItem:appItem];

    NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:@"Jnlr"] autorelease];
    [appItem setSubmenu:appMenu];
    [appMenu addItemWithTitle:@"Quit Jnlr" action:@selector(terminate:) keyEquivalent:@"q"];

    NSMenuItem *fileItem = [[[NSMenuItem alloc] initWithTitle:@"File" action:NULL keyEquivalent:@""] autorelease];
    [mainMenu addItem:fileItem];

    NSMenu *fileMenu = [[[NSMenu alloc] initWithTitle:@"File"] autorelease];
    [fileItem setSubmenu:fileMenu];
    [fileMenu addItemWithTitle:@"Open Journal…" action:@selector(openJournal:) keyEquivalent:@"o"];
    [fileMenu addItemWithTitle:@"Save" action:@selector(saveDocument:) keyEquivalent:@"s"];
    [fileMenu addItemWithTitle:@"Reload Journal" action:@selector(reloadJournal:) keyEquivalent:@"r"];
}

- (void)buildWindow
{
    NSRect frame = NSMakeRect(120, 120, 1200, 760);
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:(NSWindowStyleMaskTitled |
                                                     NSWindowStyleMaskClosable |
                                                     NSWindowStyleMaskResizable |
                                                     NSWindowStyleMaskMiniaturizable)
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [_window setTitle:@"Jnlr"];
    [_window setFrameAutosaveName:JLRWindowAutosaveName];

    NSView *contentView = [_window contentView];
    NSSplitView *outerSplitView = [[[NSSplitView alloc] initWithFrame:[contentView bounds]] autorelease];
    [outerSplitView setVertical:YES];
    [outerSplitView setDividerStyle:NSSplitViewDividerStyleThin];
    [outerSplitView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [contentView addSubview:outerSplitView];

    NSScrollView *sidebarScroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 220, NSHeight([outerSplitView bounds]))] autorelease];
    [sidebarScroll setHasVerticalScroller:YES];
    [sidebarScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    _sidebarView = [[NSOutlineView alloc] initWithFrame:[sidebarScroll bounds]];
    NSTableColumn *sidebarColumn = [[[NSTableColumn alloc] initWithIdentifier:@"sidebar"] autorelease];
    [sidebarColumn setTitle:@"Collections"];
    [sidebarColumn setWidth:200];
    [_sidebarView addTableColumn:sidebarColumn];
    [_sidebarView setOutlineTableColumn:sidebarColumn];
    [_sidebarView setHeaderView:nil];
    [_sidebarView setDelegate:self];
    [_sidebarView setDataSource:self];
    [_sidebarView setUsesAlternatingRowBackgroundColors:YES];
    [_sidebarView setAllowsEmptySelection:NO];
    [_sidebarView setRowHeight:28];
    [sidebarScroll setDocumentView:_sidebarView];
    [outerSplitView addSubview:sidebarScroll];

    NSSplitView *contentSplitView = [[[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 980, NSHeight([outerSplitView bounds]))] autorelease];
    [contentSplitView setVertical:YES];
    [contentSplitView setDividerStyle:NSSplitViewDividerStyleThin];
    [contentSplitView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [outerSplitView addSubview:contentSplitView];

    NSScrollView *tableScroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 340, NSHeight([contentSplitView bounds]))] autorelease];
    [tableScroll setHasVerticalScroller:YES];
    [tableScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    _tableView = [[NSTableView alloc] initWithFrame:[tableScroll bounds]];
    NSTableColumn *titleColumn = [[[NSTableColumn alloc] initWithIdentifier:@"title"] autorelease];
    [titleColumn setTitle:@"Title"];
    [titleColumn setWidth:220];
    [titleColumn setSortDescriptorPrototype:[[[NSSortDescriptor alloc] initWithKey:@"title" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)] autorelease]];
    [_tableView addTableColumn:titleColumn];

    NSTableColumn *dateColumn = [[[NSTableColumn alloc] initWithIdentifier:@"date"] autorelease];
    [dateColumn setTitle:@"Date"];
    [dateColumn setWidth:110];
    [dateColumn setSortDescriptorPrototype:[[[NSSortDescriptor alloc] initWithKey:@"date" ascending:NO] autorelease]];
    [_tableView addTableColumn:dateColumn];

    NSTableColumn *categoryColumn = [[[NSTableColumn alloc] initWithIdentifier:@"category"] autorelease];
    [categoryColumn setTitle:@"Category"];
    [categoryColumn setWidth:110];
    [categoryColumn setSortDescriptorPrototype:[[[NSSortDescriptor alloc] initWithKey:@"category" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)] autorelease]];
    [_tableView addTableColumn:categoryColumn];

    NSTableColumn *tagsColumn = [[[NSTableColumn alloc] initWithIdentifier:@"tags"] autorelease];
    [tagsColumn setTitle:@"Tags"];
    [tagsColumn setWidth:180];
    [tagsColumn setSortDescriptorPrototype:[[[NSSortDescriptor alloc] initWithKey:@"tags" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)] autorelease]];
    [_tableView addTableColumn:tagsColumn];

    [_tableView setDelegate:self];
    [_tableView setDataSource:self];
    [_tableView setUsesAlternatingRowBackgroundColors:YES];
    [_tableView setAllowsEmptySelection:YES];
    [_tableView setRowHeight:24];
    [_tableView setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
    [_tableView setSortDescriptors:[NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"date" ascending:NO] autorelease]]];
    [tableScroll setDocumentView:_tableView];
    [contentSplitView addSubview:tableScroll];

    NSView *detailView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 860, NSHeight([contentSplitView bounds]))] autorelease];
    [detailView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    _titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, NSHeight([detailView bounds]) - 56, NSWidth([detailView bounds]) - 40, 28)];
    [_titleLabel setBezeled:NO];
    [_titleLabel setDrawsBackground:NO];
    [_titleLabel setEditable:YES];
    [_titleLabel setSelectable:YES];
    [_titleLabel setFont:[NSFont boldSystemFontOfSize:20]];
    [_titleLabel setDelegate:self];
    [_titleLabel setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [_titleLabel setStringValue:@"No entry selected"];
    [detailView addSubview:_titleLabel];

    _summaryLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, NSHeight([detailView bounds]) - 84, NSWidth([detailView bounds]) - 40, 20)];
    [_summaryLabel setBezeled:NO];
    [_summaryLabel setDrawsBackground:NO];
    [_summaryLabel setEditable:NO];
    [_summaryLabel setSelectable:NO];
    [_summaryLabel setTextColor:[NSColor secondaryLabelColor]];
    [_summaryLabel setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [detailView addSubview:_summaryLabel];

    _metaLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, NSHeight([detailView bounds]) - 128, NSWidth([detailView bounds]) - 40, 40)];
    [_metaLabel setBezeled:NO];
    [_metaLabel setDrawsBackground:NO];
    [_metaLabel setEditable:NO];
    [_metaLabel setSelectable:NO];
    [_metaLabel setTextColor:[NSColor secondaryLabelColor]];
    [_metaLabel setUsesSingleLineMode:NO];
    [[_metaLabel cell] setWraps:YES];
    [[_metaLabel cell] setScrollable:NO];
    [_metaLabel setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [detailView addSubview:_metaLabel];

    _statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 12, NSWidth([detailView bounds]) - 40, 36)];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setEditable:NO];
    [_statusLabel setSelectable:NO];
    [_statusLabel setTextColor:[NSColor secondaryLabelColor]];
    [_statusLabel setUsesSingleLineMode:NO];
    [[_statusLabel cell] setWraps:YES];
    [[_statusLabel cell] setScrollable:NO];
    [_statusLabel setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [detailView addSubview:_statusLabel];

    NSScrollView *textScroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(20, 56, NSWidth([detailView bounds]) - 40, NSHeight([detailView bounds]) - 196)] autorelease];
    [textScroll setHasVerticalScroller:YES];
    [textScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    _textView = [[NSTextView alloc] initWithFrame:[[textScroll contentView] bounds]];
    [_textView setEditable:YES];
    [_textView setRichText:YES];
    [_textView setImportsGraphics:YES];
    [_textView setUsesFindPanel:YES];
    [_textView setDelegate:self];
    [textScroll setDocumentView:_textView];
    [detailView addSubview:textScroll];

    [contentSplitView addSubview:detailView];
    [contentSplitView adjustSubviews];
    [contentSplitView setPosition:340 ofDividerAtIndex:0];
    [outerSplitView adjustSubviews];
    [outerSplitView setPosition:220 ofDividerAtIndex:0];
}

- (void)setEntriesFromJournal:(JLRCompatJournal *)journal
{
    NSArray *sortedEntries = [[journal entries] sortedArrayUsingFunction:JLREntrySort context:NULL];

    [_allEntries release];
    _allEntries = [sortedEntries copy];

    [_entries release];
    _entries = [sortedEntries copy];
}

- (void)rebuildSidebarItems
{
    NSMutableArray *roots = [NSMutableArray array];
    JLRSidebarNode *allEntriesNode = [[[JLRSidebarNode alloc] initWithTitle:@"All Entries" collection:nil] autorelease];
    [roots addObject:allEntriesNode];

    NSArray *sortedCollections = [[_journal collections] sortedArrayUsingFunction:JLRCollectionSort context:NULL];
    NSMutableDictionary *nodesByTag = [NSMutableDictionary dictionary];

    for (JournlerCollection *collection in sortedCollections) {
        NSString *title = [collection title];
        if ([title length] == 0) {
            title = @"(untitled collection)";
        }
        JLRSidebarNode *node = [[[JLRSidebarNode alloc] initWithTitle:title collection:collection] autorelease];
        NSNumber *tagID = [collection tagID];
        if (tagID != nil) {
            [nodesByTag setObject:node forKey:tagID];
        }
    }

    for (JournlerCollection *collection in sortedCollections) {
        JLRSidebarNode *node = [nodesByTag objectForKey:[collection tagID]];
        NSNumber *parentID = [collection parentID];
        JLRSidebarNode *parentNode = (parentID != nil ? [nodesByTag objectForKey:parentID] : nil);

        if (parentNode != nil && [parentID integerValue] >= 0) {
            [parentNode addChild:node];
        } else {
            [roots addObject:node];
        }
    }

    [_sidebarItems release];
    _sidebarItems = [roots copy];
}

- (NSArray *)sortedEntriesArrayFromArray:(NSArray *)entries
{
    NSArray *sortDescriptors = [_tableView sortDescriptors];
    if ([sortDescriptors count] == 0) {
        return entries;
    }

    return [entries sortedArrayUsingComparator:^NSComparisonResult(JournlerEntry *leftEntry, JournlerEntry *rightEntry) {
        for (NSSortDescriptor *descriptor in sortDescriptors) {
            id leftValue = JLRSortValueForEntry(leftEntry, [descriptor key]);
            id rightValue = JLRSortValueForEntry(rightEntry, [descriptor key]);
            NSComparisonResult result = NSOrderedSame;

            if ([leftValue respondsToSelector:@selector(compare:)]) {
                result = (NSComparisonResult)[leftValue compare:rightValue];
            } else {
                result = [[leftValue description] localizedCaseInsensitiveCompare:[rightValue description]];
            }

            if (!descriptor.ascending) {
                if (result == NSOrderedAscending) result = NSOrderedDescending;
                else if (result == NSOrderedDescending) result = NSOrderedAscending;
            }

            if (result != NSOrderedSame) {
                return result;
            }
        }

        return JLREntrySort(leftEntry, rightEntry, NULL);
    }];
}

- (void)applySidebarSelection
{
    id item = [_sidebarView itemAtRow:[_sidebarView selectedRow]];
    if (item == nil && [_sidebarItems count] > 0) {
        item = [_sidebarItems objectAtIndex:0];
    }

    JournlerCollection *collection = [item collection];
    NSArray *visibleEntries = nil;

    if (collection == nil) {
        visibleEntries = _allEntries;
    } else {
        NSSet *entryIDs = [NSSet setWithArray:[collection entryIDs] ?: [NSArray array]];
        NSMutableArray *filtered = [NSMutableArray array];
        for (JournlerEntry *entry in _allEntries) {
            if ([entryIDs containsObject:[entry tagID]]) {
                [filtered addObject:entry];
            }
        }
        visibleEntries = filtered;
    }

    visibleEntries = [self sortedEntriesArrayFromArray:visibleEntries];

    [_entries release];
    _entries = [visibleEntries copy];
    [_tableView reloadData];

    if ([_entries count] > 0) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self refreshSelectedEntry];
    } else {
        [_titleLabel setStringValue:@"No entry selected"];
        [_summaryLabel setStringValue:@""];
        [_metaLabel setStringValue:@""];
        [[_textView textStorage] setAttributedString:[[[NSAttributedString alloc] initWithString:@""] autorelease]];
    }
}

- (JournlerEntry *)currentSelectedEntry
{
    NSInteger row = [_tableView selectedRow];
    if (row < 0 || row >= (NSInteger)[_entries count]) {
        return nil;
    }
    return [_entries objectAtIndex:row];
}

- (void)updateStatusLabel
{
    if (_journal == nil) {
        [_statusLabel setStringValue:@"No journal loaded"];
        [_statusLabel setToolTip:nil];
        return;
    }

    NSString *mode = _entryHasUnsavedChanges ? @"Unsaved changes" : @"Editable";
    NSString *journalPath = [_journal path] ?: @"";
    [_statusLabel setStringValue:[NSString stringWithFormat:@"%@. %@ entries, %@ resources, %@ collections\n%@",
                                  mode,
                                  @([_entries count]),
                                  @([[_journal resources] count]),
                                  @([[_journal collections] count]),
                                  journalPath]];
    [_statusLabel setToolTip:journalPath];
}

- (void)markSelectedEntryDirty
{
    if (_isRefreshingEditor || [self currentSelectedEntry] == nil) {
        return;
    }

    _entryHasUnsavedChanges = YES;
    [self updateStatusLabel];
}

- (BOOL)saveSelectedEntry:(NSError **)error
{
    JournlerEntry *entry = [self currentSelectedEntry];
    if (entry == nil || _journal == nil) {
        return YES;
    }

    [entry setTitle:[_titleLabel stringValue]];
    [entry setAttributedContent:[[[_textView textStorage] copy] autorelease]];

    if (![_journal saveEntry:entry error:error]) {
        return NO;
    }

    NSNumber *selectedTag = [entry tagID];
    _entryHasUnsavedChanges = NO;
    [self setEntriesFromJournal:_journal];
    [self applySidebarSelection];

    NSInteger rowToSelect = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)[_entries count]; i++) {
        if ([[[_entries objectAtIndex:i] tagID] isEqual:selectedTag]) {
            rowToSelect = i;
            break;
        }
    }
    if (rowToSelect != NSNotFound) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:rowToSelect] byExtendingSelection:NO];
    }

    [self refreshSelectedEntry];
    [self updateStatusLabel];
    return YES;
}

- (void)saveDocument:(id)sender
{
    NSError *error = nil;
    if (![self saveSelectedEntry:&error]) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Could not save entry"];
        [alert setInformativeText:(error ? [error localizedDescription] : @"Unknown error")];
        [alert runModal];
    }
}

- (BOOL)promptToSaveIfNeeded
{
    if (!_entryHasUnsavedChanges) {
        return YES;
    }

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Save changes to this entry?"];
    [alert setInformativeText:@"This writes the updated entry and JournlerStore.dict, after creating a backup copy."];
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Discard"];
    [alert addButtonWithTitle:@"Cancel"];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        NSError *error = nil;
        if (![self saveSelectedEntry:&error]) {
            NSAlert *saveAlert = [[[NSAlert alloc] init] autorelease];
            [saveAlert setMessageText:@"Could not save entry"];
            [saveAlert setInformativeText:(error ? [error localizedDescription] : @"Unknown error")];
            [saveAlert runModal];
            return NO;
        }
        return YES;
    }

    if (response == NSAlertSecondButtonReturn) {
        _entryHasUnsavedChanges = NO;
        [self updateStatusLabel];
        return YES;
    }

    return NO;
}

- (void)openJournalAtPath:(NSString *)path
{
    if (![self promptToSaveIfNeeded]) {
        return;
    }

    NSError *error = nil;
    JLRCompatJournal *journal = [[JLRCompatJournal alloc] initWithPath:[path stringByStandardizingPath]];
    if (![journal load:&error]) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Could not open journal"];
        [alert setInformativeText:(error ? [error localizedDescription] : @"Unknown error")];
        [alert runModal];
        [journal release];
        return;
    }

    [_journal release];
    _journal = journal;
    _entryHasUnsavedChanges = NO;

    [self setEntriesFromJournal:_journal];
    [self rebuildSidebarItems];
    [_sidebarView reloadData];
    [_sidebarView expandItem:nil expandChildren:YES];
    [_sidebarView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self applySidebarSelection];
    [_tableView reloadData];

    [_window setTitle:[NSString stringWithFormat:@"Jnlr - %@", [[_journal properties] objectForKey:@"Title"] ?: @"Journal"]];
    [self updateStatusLabel];

    if ([_entries count] == 0) {
        [_titleLabel setStringValue:@"No entry selected"];
        [_summaryLabel setStringValue:@""];
        [_metaLabel setStringValue:@""];
        [[_textView textStorage] setAttributedString:[[[NSAttributedString alloc] initWithString:@""] autorelease]];
    }
}

- (void)openJournal:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:YES];
    [panel setCanChooseFiles:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setPrompt:@"Open"];

    if ([panel runModal] == NSModalResponseOK) {
        NSURL *url = [[panel URLs] count] > 0 ? [[panel URLs] objectAtIndex:0] : nil;
        if (url != nil) {
            [self openJournalAtPath:[url path]];
        }
    }
}

- (void)reloadJournal:(id)sender
{
    if (_journal != nil) {
        if (![self promptToSaveIfNeeded]) {
            return;
        }
        [self openJournalAtPath:[_journal path]];
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [_entries count];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    if (outlineView != _sidebarView) {
        return 0;
    }

    if (item == nil) {
        return [_sidebarItems count];
    }

    return [[item children] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    if (outlineView != _sidebarView) {
        return nil;
    }

    if (item == nil) {
        return [_sidebarItems objectAtIndex:index];
    }

    return [[item children] objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    return ([[item children] count] > 0);
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    static NSString *sidebarIdentifier = @"SidebarCell";
    NSTableCellView *cell = [outlineView makeViewWithIdentifier:sidebarIdentifier owner:self];
    if (cell == nil) {
        cell = [[[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, [tableColumn width], 24)] autorelease];
        NSTextField *textField = [[[NSTextField alloc] initWithFrame:NSMakeRect(6, 4, [tableColumn width] - 12, 18)] autorelease];
        [textField setBezeled:NO];
        [textField setDrawsBackground:NO];
        [textField setEditable:NO];
        [textField setSelectable:NO];
        [textField setFont:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium]];
        [cell setIdentifier:sidebarIdentifier];
        [cell setTextField:textField];
        [cell addSubview:textField];
    }

    NSString *title = [item title];
    JournlerCollection *collection = [item collection];
    if (collection != nil) {
        title = [NSString stringWithFormat:@"%@ (%lu)", title, (unsigned long)[[collection entryIDs] count]];
    } else {
        title = [NSString stringWithFormat:@"%@ (%lu)", title, (unsigned long)[_allEntries count]];
    }
    [[cell textField] setStringValue:title];
    return cell;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSString *identifier = [NSString stringWithFormat:@"EntryCell-%@", [tableColumn identifier]];
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (cell == nil) {
        cell = [[[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, [tableColumn width], 22)] autorelease];
        NSTextField *textField = [[[NSTextField alloc] initWithFrame:NSMakeRect(6, 2, [tableColumn width] - 12, 18)] autorelease];
        [textField setBezeled:NO];
        [textField setDrawsBackground:NO];
        [textField setEditable:NO];
        [textField setSelectable:NO];
        if ([[tableColumn identifier] isEqualToString:@"title"]) {
            [textField setFont:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium]];
        } else {
            [textField setFont:[NSFont systemFontOfSize:12]];
            [textField setTextColor:[NSColor secondaryLabelColor]];
        }

        [cell setIdentifier:identifier];
        [cell setTextField:textField];
        [cell addSubview:textField];
    }

    JournlerEntry *entry = [_entries objectAtIndex:row];
    NSString *value = @"";
    NSString *columnIdentifier = [tableColumn identifier];
    if ([columnIdentifier isEqualToString:@"title"]) {
        NSString *title = [entry title];
        value = (title != nil && [title length] > 0) ? title : @"(untitled)";
    } else if ([columnIdentifier isEqualToString:@"date"]) {
        value = JLRFormatDate([entry creationDate]);
    } else if ([columnIdentifier isEqualToString:@"category"]) {
        value = [entry category] ?: @"";
    } else if ([columnIdentifier isEqualToString:@"tags"]) {
        value = JLRJoinTags([entry tags]);
    }

    [[cell textField] setStringValue:value ?: @""];
    return cell;
}

- (void)refreshSelectedEntry
{
    _isRefreshingEditor = YES;
    NSInteger row = [_tableView selectedRow];
    if (row < 0 || row >= (NSInteger)[_entries count]) {
        _selectedEntry = nil;
        [_titleLabel setStringValue:@"No entry selected"];
        [_summaryLabel setStringValue:@""];
        [_metaLabel setStringValue:@""];
        [[_textView textStorage] setAttributedString:[[[NSAttributedString alloc] initWithString:@""] autorelease]];
        _isRefreshingEditor = NO;
        return;
    }

    JournlerEntry *entry = [_entries objectAtIndex:row];
    _selectedEntry = entry;
    [_titleLabel setStringValue:([entry title] && [[entry title] length] > 0) ? [entry title] : @"(untitled)"];
    [_summaryLabel setStringValue:JLRListSubtitleForEntry(entry)];

    NSString *created = JLRFormatDate([entry creationDate]);
    NSString *modified = JLRFormatDate([entry modificationDate]);
    NSString *category = [entry category] ?: @"";
    NSString *tags = JLRJoinTags([entry tags]);
    [_metaLabel setStringValue:[NSString stringWithFormat:@"Created: %@    Modified: %@\nCategory: %@    Tags: %@    Entry ID: %@",
                                ([created length] > 0 ? created : @"-"),
                                ([modified length] > 0 ? modified : @"-"),
                                ([category length] > 0 ? category : @"-"),
                                ([tags length] > 0 ? tags : @"-"),
                                [entry tagID] ?: @"-"]];

    NSError *error = nil;
    NSAttributedString *content = [entry loadAttributedContent:&error];
    if (content != nil) {
        [[_textView textStorage] setAttributedString:content];
    } else {
        NSString *message = [NSString stringWithFormat:@"Could not load entry body.\n\n%@", error ? [error localizedDescription] : @"Unknown error"];
        [[_textView textStorage] setAttributedString:[[[NSAttributedString alloc] initWithString:message] autorelease]];
    }
    _entryHasUnsavedChanges = NO;
    _isRefreshingEditor = NO;
    [self updateStatusLabel];
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
    if (row == [_tableView selectedRow]) {
        return YES;
    }
    return [self promptToSaveIfNeeded];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
    if (outlineView != _sidebarView) {
        return YES;
    }

    if (item == [_sidebarView itemAtRow:[_sidebarView selectedRow]]) {
        return YES;
    }

    return [self promptToSaveIfNeeded];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [self refreshSelectedEntry];
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors
{
    if (tableView != _tableView) {
        return;
    }

    NSNumber *selectedTag = [[self currentSelectedEntry] tagID];
    [self applySidebarSelection];

    if (selectedTag != nil) {
        NSInteger rowToSelect = NSNotFound;
        for (NSInteger i = 0; i < (NSInteger)[_entries count]; i++) {
            if ([[[_entries objectAtIndex:i] tagID] isEqual:selectedTag]) {
                rowToSelect = i;
                break;
            }
        }
        if (rowToSelect != NSNotFound) {
            [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:rowToSelect] byExtendingSelection:NO];
            [self refreshSelectedEntry];
        }
    }
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
    if ([notification object] == _sidebarView) {
        [self applySidebarSelection];
    }
}

- (void)controlTextDidChange:(NSNotification *)notification
{
    [self markSelectedEntryDirty];
}

- (void)textDidChange:(NSNotification *)notification
{
    [self markSelectedEntryDirty];
}

@end

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        NSArray *arguments = [[NSProcessInfo processInfo] arguments];
        if ([arguments count] >= 3 && [[arguments objectAtIndex:1] isEqualToString:@"--smoke-test"]) {
            return JLRRunSmokeTest([[arguments objectAtIndex:2] stringByStandardizingPath]);
        }

        NSString *initialPath = nil;
        if ([arguments count] >= 2) {
            initialPath = [[arguments objectAtIndex:1] stringByStandardizingPath];
        }

        [NSApplication sharedApplication];
        JLRAppDelegate *delegate = [[[JLRAppDelegate alloc] initWithInitialJournalPath:initialPath] autorelease];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp setDelegate:delegate];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run];
    }

    return 0;
}
