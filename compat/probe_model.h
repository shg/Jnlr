#import <Cocoa/Cocoa.h>

@interface JournlerObject : NSObject <NSCoding>
+ (NSString *)tagIDKey;
+ (NSString *)titleKey;
- (NSDictionary *)properties;
- (NSNumber *)tagID;
- (NSString *)title;
- (void)setTitle:(NSString *)title;
- (NSString *)sourceJournalPath;
- (void)setSourceJournalPath:(NSString *)path;
- (void)mergeArchivedProperties:(NSDictionary *)properties;
@end

@interface JournlerEntry : JournlerObject
- (NSDate *)creationDate;
- (NSDate *)modificationDate;
- (NSString *)category;
- (NSArray *)tags;
- (NSString *)packagePath;
- (NSString *)attributedContentPath;
- (NSAttributedString *)attributedContent;
- (void)setAttributedContent:(NSAttributedString *)content;
- (NSAttributedString *)loadAttributedContent:(NSError **)error;
- (NSArray *)resourceIDs;
@end

@interface JournlerCollection : JournlerObject
@end

@interface JournlerResource : JournlerObject
@end

@interface BlogPref : JournlerObject
@end

@interface JLRCompatJournal : NSObject
- (instancetype)initWithPath:(NSString *)path;
- (BOOL)load:(NSError **)error;
- (NSString *)path;
- (BOOL)loadedFromStore;
- (BOOL)saveEntry:(JournlerEntry *)entry error:(NSError **)error;
- (NSDictionary *)properties;
- (NSArray *)entries;
- (NSArray *)collections;
- (NSArray *)resources;
- (NSArray *)blogs;
- (NSArray *)entryDecodeIssues;
@end
