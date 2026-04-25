#import <Cocoa/Cocoa.h>

#import "../compat/probe_model.h"

static NSString *JLRWindowAutosaveName = @"JnlrMainWindow";

@interface JLRAppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate>
{
    NSWindow *_window;
    NSTableView *_tableView;
    NSTextView *_textView;
    NSTextField *_titleLabel;
    NSTextField *_metaLabel;
    NSTextField *_statusLabel;
    JLRCompatJournal *_journal;
    NSArray *_entries;
    NSString *_initialJournalPath;
}

- (instancetype)initWithInitialJournalPath:(NSString *)path;
- (void)openJournalAtPath:(NSString *)path;
- (void)openJournal:(id)sender;
- (void)reloadJournal:(id)sender;
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

@implementation JLRAppDelegate

- (instancetype)initWithInitialJournalPath:(NSString *)path
{
    self = [super init];
    if (self) {
        _initialJournalPath = [path copy];
        _entries = [[NSArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_window release];
    [_tableView release];
    [_textView release];
    [_titleLabel release];
    [_metaLabel release];
    [_statusLabel release];
    [_journal release];
    [_entries release];
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
    NSSplitView *splitView = [[[NSSplitView alloc] initWithFrame:[contentView bounds]] autorelease];
    [splitView setVertical:YES];
    [splitView setDividerStyle:NSSplitViewDividerStyleThin];
    [splitView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [contentView addSubview:splitView];

    NSScrollView *tableScroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 340, NSHeight([splitView bounds]))] autorelease];
    [tableScroll setHasVerticalScroller:YES];
    [tableScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    _tableView = [[NSTableView alloc] initWithFrame:[tableScroll bounds]];
    NSTableColumn *titleColumn = [[[NSTableColumn alloc] initWithIdentifier:@"title"] autorelease];
    [titleColumn setTitle:@"Entries"];
    [titleColumn setWidth:320];
    [_tableView addTableColumn:titleColumn];
    [_tableView setHeaderView:nil];
    [_tableView setDelegate:self];
    [_tableView setDataSource:self];
    [_tableView setUsesAlternatingRowBackgroundColors:YES];
    [_tableView setAllowsEmptySelection:YES];
    [tableScroll setDocumentView:_tableView];
    [splitView addSubview:tableScroll];

    NSView *detailView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 860, NSHeight([splitView bounds]))] autorelease];
    [detailView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    _titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, NSHeight([detailView bounds]) - 56, NSWidth([detailView bounds]) - 40, 28)];
    [_titleLabel setBezeled:NO];
    [_titleLabel setDrawsBackground:NO];
    [_titleLabel setEditable:NO];
    [_titleLabel setSelectable:NO];
    [_titleLabel setFont:[NSFont boldSystemFontOfSize:20]];
    [_titleLabel setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [_titleLabel setStringValue:@"No entry selected"];
    [detailView addSubview:_titleLabel];

    _metaLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, NSHeight([detailView bounds]) - 84, NSWidth([detailView bounds]) - 40, 20)];
    [_metaLabel setBezeled:NO];
    [_metaLabel setDrawsBackground:NO];
    [_metaLabel setEditable:NO];
    [_metaLabel setSelectable:NO];
    [_metaLabel setTextColor:[NSColor secondaryLabelColor]];
    [_metaLabel setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [detailView addSubview:_metaLabel];

    _statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 16, NSWidth([detailView bounds]) - 40, 20)];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setEditable:NO];
    [_statusLabel setSelectable:NO];
    [_statusLabel setTextColor:[NSColor secondaryLabelColor]];
    [_statusLabel setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [detailView addSubview:_statusLabel];

    NSScrollView *textScroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(20, 48, NSWidth([detailView bounds]) - 40, NSHeight([detailView bounds]) - 144)] autorelease];
    [textScroll setHasVerticalScroller:YES];
    [textScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    _textView = [[NSTextView alloc] initWithFrame:[[textScroll contentView] bounds]];
    [_textView setEditable:NO];
    [_textView setRichText:YES];
    [_textView setImportsGraphics:YES];
    [_textView setUsesFindPanel:YES];
    [textScroll setDocumentView:_textView];
    [detailView addSubview:textScroll];

    [splitView addSubview:detailView];
    [splitView adjustSubviews];
    [splitView setPosition:340 ofDividerAtIndex:0];
}

- (void)setEntriesFromJournal:(JLRCompatJournal *)journal
{
    NSArray *sortedEntries = [[journal entries] sortedArrayUsingFunction:JLREntrySort context:NULL];

    [_entries release];
    _entries = [sortedEntries copy];
}

- (void)openJournalAtPath:(NSString *)path
{
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

    [self setEntriesFromJournal:_journal];
    [_tableView reloadData];

    [_window setTitle:[NSString stringWithFormat:@"Jnlr - %@", [[_journal properties] objectForKey:@"Title"] ?: @"Journal"]];
    [_statusLabel setStringValue:[NSString stringWithFormat:@"Read-only mode. %@ entries, %@ resources, %@ collections",
                                  @([_entries count]),
                                  @([[_journal resources] count]),
                                  @([[_journal collections] count])]];

    if ([_entries count] > 0) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self refreshSelectedEntry];
    } else {
        [_titleLabel setStringValue:@"No entry selected"];
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
        [self openJournalAtPath:[_journal path]];
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [_entries count];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    static NSString *identifier = @"EntryCell";
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (cell == nil) {
        cell = [[[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, [tableColumn width], 22)] autorelease];
        NSTextField *textField = [[[NSTextField alloc] initWithFrame:NSMakeRect(8, 1, [tableColumn width] - 16, 20)] autorelease];
        [textField setBezeled:NO];
        [textField setDrawsBackground:NO];
        [textField setEditable:NO];
        [textField setSelectable:NO];
        [cell setIdentifier:identifier];
        [cell setTextField:textField];
        [cell addSubview:textField];
    }

    JournlerEntry *entry = [_entries objectAtIndex:row];
    NSString *title = [entry title];
    [[cell textField] setStringValue:(title != nil && [title length] > 0) ? title : @"(untitled)"];
    return cell;
}

- (void)refreshSelectedEntry
{
    NSInteger row = [_tableView selectedRow];
    if (row < 0 || row >= (NSInteger)[_entries count]) {
        [_titleLabel setStringValue:@"No entry selected"];
        [_metaLabel setStringValue:@""];
        [[_textView textStorage] setAttributedString:[[[NSAttributedString alloc] initWithString:@""] autorelease]];
        return;
    }

    JournlerEntry *entry = [_entries objectAtIndex:row];
    [_titleLabel setStringValue:([entry title] && [[entry title] length] > 0) ? [entry title] : @"(untitled)"];
    [_metaLabel setStringValue:[NSString stringWithFormat:@"Tag %@   %@", [entry tagID] ?: @"-", JLRFormatDate([entry creationDate])]];

    NSError *error = nil;
    NSAttributedString *content = [entry loadAttributedContent:&error];
    if (content != nil) {
        [[_textView textStorage] setAttributedString:content];
    } else {
        NSString *message = [NSString stringWithFormat:@"Could not load entry body.\n\n%@", error ? [error localizedDescription] : @"Unknown error"];
        [[_textView textStorage] setAttributedString:[[[NSAttributedString alloc] initWithString:message] autorelease]];
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [self refreshSelectedEntry];
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
