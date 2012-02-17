//
//  iPhone OAuth Starter Kit
//
//  Supported providers: LinkedIn (OAuth 1.0a)
//
//  Lee Whitney
//  http://whitneyland.com
//
#import <UIKit/UIKit.h>
#import "JSONKit.h"
#import "OAConsumer.h"
#import "OAMutableURLRequest.h"
#import "OADataFetcher.h"
#import "Profile.h"
#import "LinkedInDataFetcher.h"
#import "CanWeNetworkAPIClient.h"
#import "Utilities.h"


@interface OAuthLoginView : UIViewController <UIWebViewDelegate, LinkedInDataFetcherDelegate>
{
    IBOutlet UIWebView *webView;
    UIActivityIndicatorView *activityIndicator;
    IBOutlet UIButton *backButton;
    IBOutlet UIView *activityOverlayView;
    
    OAToken *requestToken;
    OAToken *accessToken;
    
    OADataFetcher *requestTokenFetcher;
    OADataFetcher *accessTokenFetcher;
    LinkedInDataFetcher *linkedInDataFetcher;
    
    NSDictionary *profileDict;
    
    // Theses ivars could be made into a provider class
    // Then you could pass in different providers for Twitter, LinkedIn, etc
    NSString *apikey;
    NSString *secretkey;
    NSString *requestTokenURLString;
    NSURL *requestTokenURL;
    NSString *accessTokenURLString;
    NSURL *accessTokenURL;
    NSString *userLoginURLString;
    NSURL *userLoginURL;
    NSString *linkedInCallbackURL;
    OAConsumer *consumer;
}

@property(nonatomic, retain) OAToken *requestToken;
@property(nonatomic, retain) OAToken *accessToken;
@property(nonatomic, retain) NSDictionary *profileDict;
@property(nonatomic, retain) Profile *profile;
@property(nonatomic, retain) OAConsumer *consumer;

- (void)initLinkedInApi;
- (void)requestTokenFromProvider;
- (void)allowUserToLogin;
- (void)accessTokenFromProvider;
- (void)linkedInProfileCall;

- (id)initWithProfile:(Profile *)aProfile;

@end
