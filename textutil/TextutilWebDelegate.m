#import "TextutilWebDelegate.h"

NSURL *textutilBaseURLForWebResources;

@implementation TextutilWebDelegate

- (id)webView:(id)webView identifierForInitialRequest:(id)request fromDataSource:(id)dataSource
{
    (void)webView;
    (void)dataSource;
    return request;
}

- (id)webView:(id)webView resource:(id)resource willSendRequest:(id)request redirectResponse:(id)redirectResponse fromDataSource:(id)dataSource
{
    id requestURL;
    id baseURL;
    unsigned char matchesBaseURL;

    (void)webView;
    (void)resource;
    (void)redirectResponse;
    (void)dataSource;

    requestURL = [request URL];
    baseURL = textutilBaseURLForWebResources;
    matchesBaseURL = (unsigned char)[requestURL isEqual:baseURL];
    if (!matchesBaseURL && requestURL && baseURL) {
        id absoluteRequestURL;
        id absoluteBaseURL;

        absoluteRequestURL = [requestURL absoluteURL];
        absoluteBaseURL = [baseURL absoluteURL];
        if ((unsigned char)[absoluteRequestURL isEqual:absoluteBaseURL]) {
            return request;
        }
        if (!(unsigned char)[absoluteBaseURL isFileURL] || !(unsigned char)[absoluteRequestURL isFileURL]) {
            return nil;
        }
        matchesBaseURL = (unsigned char)[[absoluteRequestURL path] isEqual:[absoluteBaseURL path]];
    }
    if (!matchesBaseURL) {
        return nil;
    }
    return request;
}

- (void)webView:(id)webView resource:(id)resource didReceiveAuthenticationChallenge:(id)challenge fromDataSource:(id)dataSource
{
    id sender;

    (void)webView;
    (void)resource;
    (void)dataSource;

    sender = [challenge sender];
    [sender cancelAuthenticationChallenge:challenge];
}

@end
