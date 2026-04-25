#import "probe_model.h"

static NSString * const JLRPropertiesFilename = @"Journler.plist";
static NSString * const JLRStoreFilename = @"JournlerStore.dict";
static NSString * const JLREntryRTFDFilename = @"Entry.rtfd";
static NSString * const JLREntryRTFFilename = @"TXT.rtf";
static NSString * const JLREntryContentsFilename = @"Contents.jobj";
static NSString * const JLREntriesDirectoryName = @"Journler Entries";
static NSString * const JLRCollectionsDirectoryName = @"Collections";
static NSString * const JLRResourcesDirectoryName = @"Resources";
static NSString * const JLRBlogsDirectoryName = @"Blogs";

@interface JournlerObject ()
{
    NSMutableDictionary *_properties;
    NSString *_sourceJournalPath;
}
@end

@implementation JournlerObject

+ (NSString *)tagIDKey
{
    return @"tagID";
}

+ (NSString *)titleKey
{
    return @"title";
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _properties = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_properties release];
    [_sourceJournalPath release];
    [super dealloc];
}

- (NSDictionary *)properties
{
    return _properties;
}

- (void)mergeArchivedProperties:(NSDictionary *)properties
{
    if ([properties isKindOfClass:[NSDictionary class]]) {
        [_properties addEntriesFromDictionary:properties];
    }
}

- (NSString *)sourceJournalPath
{
    return _sourceJournalPath;
}

- (void)setSourceJournalPath:(NSString *)path
{
    if (_sourceJournalPath != path) {
        [_sourceJournalPath release];
        _sourceJournalPath = [path copy];
    }
}

- (NSNumber *)tagID
{
    id value = [_properties objectForKey:[[self class] tagIDKey]];
    return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

- (NSString *)title
{
    id value = [_properties objectForKey:[[self class] titleKey]];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [self init];
    if (!self) {
        return nil;
    }

    NSDictionary *archivedProperties = [decoder decodeObjectForKey:@"properties"];
    [self mergeArchivedProperties:archivedProperties];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeObject:_properties forKey:@"properties"];
}

@end

@interface JournlerEntry ()
{
    NSArray *_resourceIDs;
}
@end

@implementation JournlerEntry

+ (NSString *)tagIDKey
{
    return @"Entry Tag";
}

+ (NSString *)titleKey
{
    return @"Entry Title";
}

- (void)dealloc
{
    [_resourceIDs release];
    [super dealloc];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [self init];
    if (!self) {
        return nil;
    }

    NSDictionary *archivedProperties = [decoder decodeObjectForKey:@"JObjectProperties"];
    if (![archivedProperties isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    [self mergeArchivedProperties:archivedProperties];

    id resourceIDs = [decoder decodeObjectForKey:@"AllResourceIDs"];
    if ([resourceIDs isKindOfClass:[NSArray class]]) {
        _resourceIDs = [resourceIDs copy];
    }

    return self;
}

- (NSArray *)resourceIDs
{
    return _resourceIDs;
}

- (NSDate *)creationDate
{
    id value = [[self properties] objectForKey:@"Entry Date"];
    return [value isKindOfClass:[NSDate class]] ? value : nil;
}

- (NSString *)packagePath
{
    NSString *journalPath = [self sourceJournalPath];
    NSNumber *tagID = [self tagID];
    if (journalPath == nil || tagID == nil) {
        return nil;
    }

    NSString *entriesPath = [journalPath stringByAppendingPathComponent:@"Journler Entries"];
    NSString *entryDirectory = [NSString stringWithFormat:@"Entry %@", tagID];
    return [entriesPath stringByAppendingPathComponent:entryDirectory];
}

- (NSString *)attributedContentPath
{
    NSString *packagePath = [self packagePath];
    if (packagePath == nil) {
        return nil;
    }

    return [[packagePath stringByAppendingPathComponent:@"_Text.jrtfd"] stringByAppendingPathComponent:JLREntryRTFDFilename];
}

- (NSAttributedString *)loadAttributedContent:(NSError **)error
{
    NSString *contentPath = [self attributedContentPath];
    if (contentPath == nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"JLRCompatJournal"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Entry did not resolve to a content path"}];
        }
        return nil;
    }

    NSURL *contentURL = [NSURL fileURLWithPath:contentPath];
    NSFileWrapper *wrapper = [[[NSFileWrapper alloc] initWithURL:contentURL
                                                         options:0
                                                           error:error] autorelease];
    if (wrapper != nil) {
        NSAttributedString *rtfdContent = [[[NSAttributedString alloc] initWithRTFDFileWrapper:wrapper
                                                                            documentAttributes:NULL] autorelease];
        if (rtfdContent != nil) {
            return rtfdContent;
        }
    }

    NSString *rtfPath = [contentPath stringByAppendingPathComponent:JLREntryRTFFilename];
    NSURL *rtfURL = [NSURL fileURLWithPath:rtfPath];
    NSDictionary *options = @{NSDocumentTypeDocumentOption: NSRTFTextDocumentType};
    return [[[NSAttributedString alloc] initWithURL:rtfURL
                                            options:options
                                 documentAttributes:NULL
                                              error:error] autorelease];
}

@end

@implementation JournlerCollection

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [self init];
    if (!self) {
        return nil;
    }

    NSDictionary *archivedProperties = [decoder decodeObjectForKey:@"JCollProperties"];
    if (![archivedProperties isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    [self mergeArchivedProperties:archivedProperties];
    return self;
}

@end

@implementation JournlerResource

+ (NSString *)tagIDKey
{
    return @"ResourceTagIDKey";
}

+ (NSString *)titleKey
{
    return @"ResourceTitleKey";
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [self init];
    if (!self) {
        return nil;
    }

    NSDictionary *archivedProperties = [decoder decodeObjectForKey:@"ResourceProperties"];
    if (![archivedProperties isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    [self mergeArchivedProperties:archivedProperties];
    return self;
}

@end

@implementation BlogPref

+ (NSString *)titleKey
{
    return @"name";
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [self init];
    if (!self) {
        return nil;
    }

    NSDictionary *archivedProperties = [decoder decodeObjectForKey:@"BlogProperties"];
    if (![archivedProperties isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    [self mergeArchivedProperties:archivedProperties];
    return self;
}

@end

@interface JLRCompatJournal ()
{
    NSString *_path;
    NSDictionary *_properties;
    NSArray *_entries;
    NSArray *_collections;
    NSArray *_resources;
    NSArray *_blogs;
    NSArray *_entryDecodeIssues;
    BOOL _loadedFromStore;
}
@end

@implementation JLRCompatJournal

- (void)assignJournalPath:(NSString *)journalPath toObjects:(NSArray *)objects
{
    for (id object in objects) {
        if ([object respondsToSelector:@selector(setSourceJournalPath:)]) {
            [object setSourceJournalPath:journalPath];
        }
    }
}

- (id)unarchiveObjectAtPath:(NSString *)path issueLabel:(NSString *)issueLabel issues:(NSMutableArray *)issues
{
    id object = nil;
    @try {
        object = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
    }
    @catch (NSException *exception) {
        if (issues != nil) {
            [issues addObject:[NSString stringWithFormat:@"%@: %@", issueLabel, [exception reason]]];
        }
        return nil;
    }

    if (object == nil && issues != nil) {
        [issues addObject:[NSString stringWithFormat:@"%@: unarchived to nil", issueLabel]];
    }

    return object;
}

- (NSArray *)decodeDirectoryObjectsAtPath:(NSString *)directoryPath
                                extension:(NSString *)extension
                               issueGroup:(NSString *)issueGroup
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *contents = [manager contentsOfDirectoryAtPath:directoryPath error:NULL];
    if (![contents isKindOfClass:[NSArray class]]) {
        return [NSArray array];
    }

    NSMutableArray *decoded = [NSMutableArray array];
    NSMutableArray *issues = [NSMutableArray array];

    for (NSString *name in contents) {
        if (![[name pathExtension] isEqualToString:extension]) {
            continue;
        }

        NSString *fullPath = [directoryPath stringByAppendingPathComponent:name];
        id object = [self unarchiveObjectAtPath:fullPath
                                     issueLabel:[NSString stringWithFormat:@"%@/%@", issueGroup, name]
                                         issues:issues];
        if (object != nil) {
            [decoded addObject:object];
        }
    }

    if ([issueGroup isEqualToString:@"Entries"]) {
        [_entryDecodeIssues release];
        _entryDecodeIssues = [issues copy];
    }

    return decoded;
}

- (NSArray *)decodeEntryPackagesAtPath:(NSString *)entriesPath
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *contents = [manager contentsOfDirectoryAtPath:entriesPath error:NULL];
    if (![contents isKindOfClass:[NSArray class]]) {
        return [NSArray array];
    }

    NSMutableArray *decoded = [NSMutableArray array];
    NSMutableArray *issues = [NSMutableArray array];

    for (NSString *name in contents) {
        if ([name rangeOfString:@"Entry "].location == NSNotFound) {
            continue;
        }

        NSString *packagePath = [entriesPath stringByAppendingPathComponent:name];
        BOOL isDirectory = NO;
        if (![manager fileExistsAtPath:packagePath isDirectory:&isDirectory] || !isDirectory) {
            continue;
        }

        NSArray *propertiesFiles = [[manager contentsOfDirectoryAtPath:packagePath error:NULL] pathsMatchingExtensions:[NSArray arrayWithObject:@"jobj"]];
        NSString *propertiesPath = nil;
        if ([propertiesFiles count] == 1) {
            propertiesPath = [packagePath stringByAppendingPathComponent:[propertiesFiles objectAtIndex:0]];
        } else {
            NSString *defaultPath = [packagePath stringByAppendingPathComponent:JLREntryContentsFilename];
            if ([manager fileExistsAtPath:defaultPath]) {
                propertiesPath = defaultPath;
            } else if ([propertiesFiles count] > 0) {
                propertiesPath = [packagePath stringByAppendingPathComponent:[propertiesFiles objectAtIndex:0]];
            } else {
                propertiesPath = defaultPath;
            }
        }

        id entry = [self unarchiveObjectAtPath:propertiesPath
                                    issueLabel:[NSString stringWithFormat:@"Entries/%@", name]
                                        issues:issues];
        if (entry != nil) {
            [decoded addObject:entry];
        }
    }

    [_entryDecodeIssues release];
    _entryDecodeIssues = [issues copy];
    return decoded;
}

- (void)mergeDirectoryEntriesIfNeeded
{
    NSString *entriesPath = [_path stringByAppendingPathComponent:JLREntriesDirectoryName];
    NSArray *directoryEntries = [self decodeEntryPackagesAtPath:entriesPath];
    if ([directoryEntries count] == 0) {
        return;
    }

    NSMutableDictionary *entriesByTag = [NSMutableDictionary dictionary];
    for (JournlerEntry *entry in _entries) {
        NSNumber *tag = [entry tagID];
        if (tag != nil) {
            [entriesByTag setObject:entry forKey:tag];
        }
    }

    NSMutableArray *merged = [NSMutableArray arrayWithArray:_entries ?: [NSArray array]];
    for (JournlerEntry *entry in directoryEntries) {
        NSNumber *tag = [entry tagID];
        if (tag == nil || [entriesByTag objectForKey:tag] != nil) {
            continue;
        }
        [merged addObject:entry];
        [entriesByTag setObject:entry forKey:tag];
    }

    [_entries release];
    _entries = [merged copy];
    [self assignJournalPath:_path toObjects:_entries];
}

- (BOOL)loadFromDirectory:(NSError **)error
{
    NSString *entriesPath = [_path stringByAppendingPathComponent:JLREntriesDirectoryName];
    NSString *collectionsPath = [_path stringByAppendingPathComponent:JLRCollectionsDirectoryName];
    NSString *resourcesPath = [_path stringByAppendingPathComponent:JLRResourcesDirectoryName];
    NSString *blogsPath = [_path stringByAppendingPathComponent:JLRBlogsDirectoryName];

    [_entries release];
    _entries = [[self decodeEntryPackagesAtPath:entriesPath] copy];
    [self assignJournalPath:_path toObjects:_entries];

    [_collections release];
    _collections = [[self decodeDirectoryObjectsAtPath:collectionsPath extension:@"jcol" issueGroup:@"Collections"] copy];
    [self assignJournalPath:_path toObjects:_collections];

    [_resources release];
    _resources = [[self decodeDirectoryObjectsAtPath:resourcesPath extension:@"jresource" issueGroup:@"Resources"] copy];
    [self assignJournalPath:_path toObjects:_resources];

    [_blogs release];
    _blogs = [[self decodeDirectoryObjectsAtPath:blogsPath extension:@"jblog" issueGroup:@"Blogs"] copy];
    [self assignJournalPath:_path toObjects:_blogs];

    _loadedFromStore = NO;

    if ([_entries count] == 0 && [_collections count] == 0 && [_resources count] == 0 && [_blogs count] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"JLRCompatJournal"
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Could not decode journal contents from directories"}];
        }
        return NO;
    }

    return YES;
}

- (instancetype)initWithPath:(NSString *)path
{
    self = [super init];
    if (self) {
        _path = [path copy];
    }
    return self;
}

- (void)dealloc
{
    [_path release];
    [_properties release];
    [_entries release];
    [_collections release];
    [_resources release];
    [_blogs release];
    [_entryDecodeIssues release];
    [super dealloc];
}

- (NSArray *)decodeEntries:(NSArray *)encodedEntries
{
    NSMutableArray *decoded = [NSMutableArray arrayWithCapacity:[encodedEntries count]];
    NSMutableArray *issues = [NSMutableArray array];
    NSUInteger index = 0;
    for (id item in encodedEntries) {
        NSData *rawData = [item isKindOfClass:[NSDictionary class]] ? [item objectForKey:@"Data"] : nil;
        if (![rawData isKindOfClass:[NSData class]]) {
            [issues addObject:[NSString stringWithFormat:@"entry[%lu]: missing raw data", (unsigned long)index]];
            index++;
            continue;
        }

        id entry = nil;
        @try {
            entry = [NSKeyedUnarchiver unarchiveObjectWithData:rawData];
        }
        @catch (NSException *exception) {
            [issues addObject:[NSString stringWithFormat:@"entry[%lu]: %@", (unsigned long)index, [exception reason]]];
            index++;
            continue;
        }

        if (entry != nil) {
            [decoded addObject:entry];
        } else {
            [issues addObject:[NSString stringWithFormat:@"entry[%lu]: unarchived to nil", (unsigned long)index]];
        }
        index++;
    }
    [_entryDecodeIssues release];
    _entryDecodeIssues = [issues copy];
    return decoded;
}

- (NSArray *)decodeArchivedObjects:(NSArray *)encodedObjects
{
    NSMutableArray *decoded = [NSMutableArray arrayWithCapacity:[encodedObjects count]];
    for (id rawData in encodedObjects) {
        if (![rawData isKindOfClass:[NSData class]]) {
            continue;
        }

        id object = [NSKeyedUnarchiver unarchiveObjectWithData:rawData];
        if (object != nil) {
            [decoded addObject:object];
        }
    }
    return decoded;
}

- (BOOL)load:(NSError **)error
{
    NSString *propertiesPath = [_path stringByAppendingPathComponent:JLRPropertiesFilename];
    NSString *storePath = [_path stringByAppendingPathComponent:JLRStoreFilename];

    NSDictionary *properties = [NSDictionary dictionaryWithContentsOfFile:propertiesPath];
    if (properties == nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"JLRCompatJournal"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Could not read Journler.plist"}];
        }
        return NO;
    }

    NSDictionary *store = [NSDictionary dictionaryWithContentsOfFile:storePath];
    if (store == nil) {
        return [self loadFromDirectory:error];
    }

    NSArray *encodedEntries = [store objectForKey:@"Entries"];
    NSArray *encodedCollections = [store objectForKey:@"Collections"];
    NSArray *encodedResources = [store objectForKey:@"Resources"];
    NSArray *encodedBlogs = [store objectForKey:@"Blogs"];

    if (![encodedEntries isKindOfClass:[NSArray class]] ||
        ![encodedCollections isKindOfClass:[NSArray class]] ||
        ![encodedResources isKindOfClass:[NSArray class]] ||
        ![encodedBlogs isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"JLRCompatJournal"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Store did not contain expected arrays"}];
        }
        return NO;
    }

    [_properties release];
    _properties = [properties copy];

    [_entries release];
    _entries = [[self decodeEntries:encodedEntries] copy];
    [self assignJournalPath:_path toObjects:_entries];

    [_collections release];
    _collections = [[self decodeArchivedObjects:encodedCollections] copy];
    [self assignJournalPath:_path toObjects:_collections];

    [_resources release];
    _resources = [[self decodeArchivedObjects:encodedResources] copy];
    [self assignJournalPath:_path toObjects:_resources];

    [_blogs release];
    _blogs = [[self decodeArchivedObjects:encodedBlogs] copy];
    [self assignJournalPath:_path toObjects:_blogs];

    _loadedFromStore = YES;
    [self mergeDirectoryEntriesIfNeeded];

    return YES;
}

- (NSDictionary *)properties { return _properties; }
- (NSString *)path { return _path; }
- (BOOL)loadedFromStore { return _loadedFromStore; }
- (NSArray *)entries { return _entries; }
- (NSArray *)collections { return _collections; }
- (NSArray *)resources { return _resources; }
- (NSArray *)blogs { return _blogs; }
- (NSArray *)entryDecodeIssues { return _entryDecodeIssues; }

@end
