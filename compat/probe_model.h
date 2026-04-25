#import <Cocoa/Cocoa.h>

@interface JournlerObject : NSObject <NSCoding>
+ (NSString *)tagIDKey;
+ (NSString *)titleKey;
- (NSDictionary *)properties;
- (NSNumber *)tagID;
- (NSString *)title;
- (void)mergeArchivedProperties:(NSDictionary *)properties;
@end

@interface JournlerEntry : JournlerObject
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
- (NSDictionary *)properties;
- (NSArray *)entries;
- (NSArray *)collections;
- (NSArray *)resources;
- (NSArray *)blogs;
- (NSArray *)entryDecodeIssues;
@end
