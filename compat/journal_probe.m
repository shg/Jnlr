#import <Cocoa/Cocoa.h>

#import "probe_model.h"

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: %s /path/to/Journler\n", argv[0]);
            return 2;
        }

        NSString *journalPath = [[NSString stringWithUTF8String:argv[1]] stringByStandardizingPath];
        JLRCompatJournal *journal = [[JLRCompatJournal alloc] initWithPath:journalPath];
        NSError *error = nil;
        BOOL ok = [journal load:&error];

        printf("path=%s\n", [journalPath UTF8String]);
        printf("load_ok=%s\n", ok ? "true" : "false");
        printf("error=%s\n", error ? [[[error localizedDescription] description] UTF8String] : "<none>");
        printf("loaded_from_store=%s\n", [journal loadedFromStore] ? "true" : "false");
        printf("version=%ld\n", (long)[[[journal properties] objectForKey:@"Version"] integerValue]);
        printf("title=%s\n", [[[[journal properties] objectForKey:@"Title"] description] UTF8String]);
        printf("entries=%lu\n", (unsigned long)[[journal entries] count]);
        printf("collections=%lu\n", (unsigned long)[[journal collections] count]);
        printf("resources=%lu\n", (unsigned long)[[journal resources] count]);
        printf("blogs=%lu\n", (unsigned long)[[journal blogs] count]);
        printf("entry_decode_issues=%lu\n", (unsigned long)[[journal entryDecodeIssues] count]);

        if ([[journal entries] count] > 0) {
            id entry = [[journal entries] objectAtIndex:0];
            printf("first_entry_tag=%ld\n", (long)[[entry tagID] integerValue]);
            printf("first_entry_title=%s\n", [[[entry title] description] UTF8String]);

            NSError *contentError = nil;
            NSAttributedString *content = [entry loadAttributedContent:&contentError];
            printf("first_entry_content_ok=%s\n", content ? "true" : "false");
            printf("first_entry_content_error=%s\n",
                   contentError ? [[[contentError localizedDescription] description] UTF8String] : "<none>");
            printf("first_entry_content_length=%lu\n", (unsigned long)[content length]);
        }

        NSUInteger issueLimit = MIN((NSUInteger)5, [[journal entryDecodeIssues] count]);
        for (NSUInteger idx = 0; idx < issueLimit; idx++) {
            NSString *issue = [[journal entryDecodeIssues] objectAtIndex:idx];
            printf("entry_issue_%lu=%s\n", (unsigned long)idx, [issue UTF8String]);
        }

        [journal release];
    }

    return 0;
}
