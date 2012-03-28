//
//  iPhone OAuth Starter Kit
//
//  Supported providers: LinkedIn (OAuth 1.0a)
//
//  Lee Whitney
//  http://whitneyland.com
//
#import <Foundation/NSNotificationQueue.h>
#import "OAuthLoginView.h"
#import "Defines.h"
#import "AppDelegate.h"
#import "Profile.h"
#import "Skill.h"
#import "Industry.h"
#import "Experience.h"
#import "Education.h"
#import "PrivateInfoViewController.h"
#import "LinkedInProfileParser.h"
#import "LinkedInProfileUpdateManager.h"
#import "Utilities.h"

#define kDuplicateProfileStatus 1
#define kLinkedInRevokeUrlString @"https://www.linkedin.com/secure/settings?userAgree="
#define kLinkedInContinueUrlString @"https://www.linkedin.com/uas/oauth/authenticate?oauth_token="
#define kOAuthTokenKey @"oauth_token"
#define kOAuthTokenSecretKey @"oauth_token_secret"

@implementation OAuthLoginView

@synthesize requestToken, accessToken, profileDict, profile, consumer;
@synthesize delegate;

- (void)deleteCookies
{
    NSHTTPCookie *cookie;
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (cookie in [storage cookies]) {
        [storage deleteCookie:cookie];
    }
}

- (void)goToInApp
{
    AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];    
    [appDelegate switchToTabBarController];
}

- (void)showConnectionErrorAlert
{
    UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"Connection error"
                                                        message:@"Please check your internet connection and try again" delegate:self 
                                              cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alertView show];
    [alertView release];
}

- (void)showProfileErrorAlert
{
    UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"Connection error"
                                                        message:@"We were unable to import your LinkedIn profile. Please check your internet connection and try again." delegate:self 
                                              cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alertView show];
    [alertView release];
}

- (void)requestTokenFromProvider
{
    OAMutableURLRequest *request = 
    [[[OAMutableURLRequest alloc] initWithURL:requestTokenURL
                                     consumer:consumer
                                        token:nil   
                                     callback:linkedInCallbackURL
                            signatureProvider:nil] autorelease];
    
    [request setHTTPMethod:@"POST"];   
    requestTokenFetcher = [[OADataFetcher alloc] init];
    [requestTokenFetcher fetchDataWithRequest:request
                                     delegate:self
                            didFinishSelector:@selector(requestTokenResult:didFinish:)
                              didFailSelector:@selector(requestTokenResult:didFail:)];    
}

- (void)requestTokenResult:(OAServiceTicket *)ticket didFinish:(NSData *)data 
{
    if (ticket.didSucceed == NO) 
        return;
    
    NSString *responseBody = [[NSString alloc] initWithData:data
                                                   encoding:NSUTF8StringEncoding];
    self.requestToken = [[[OAToken alloc] initWithHTTPResponseBody:responseBody] autorelease];
    [responseBody release];
    
    [self allowUserToLogin];
}

- (void)requestTokenResult:(OAServiceTicket *)ticket didFail:(NSData *)error 
{
    NSLog(@"%@",[error description]);
    [self showConnectionErrorAlert];
}

- (void)allowUserToLogin
{
    NSString *userLoginURLWithToken = [NSString stringWithFormat:@"%@?oauth_token=%@&auth_token_secret=%@", 
                                       userLoginURLString, self.requestToken.key, self.requestToken.secret];
    
    userLoginURL = [NSURL URLWithString:userLoginURLWithToken];
    NSURLRequest *request = [NSMutableURLRequest requestWithURL: userLoginURL];
    [webView loadRequest:request];     
}

- (void)revokePermissionTapped
{    
    Profile *currentProfile = [[DataManager sharedDataManager] currentProfile];
    if ([currentProfile isCreatedWithLinkedIn]) {
        [[DataManager sharedDataManager] logout];
        [self goToInApp];
        AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];    
        [appDelegate.tabBarController setSelectedIndex:0];
    } else {
        [currentProfile deleteLinkedInInfo];
        [[DataManager sharedDataManager] postProfileToTheServer:currentProfile block:^(NSDictionary *records) {
            if(records && [records objectForKey:@"status"]) {
                [self goToInApp];
            } else {
                
            }
        }];
        
    }
    // Delete linkedin cookies to make user enter login and password next time
    [self deleteCookies];
}

- (BOOL)webView:(UIWebView*)webView shouldStartLoadWithRequest:(NSURLRequest*)request navigationType:(UIWebViewNavigationType)navigationType 
{
	NSURL *url = request.URL;
	NSString *urlString = url.absoluteString;
    
    if ([urlString isEqualToString:kLinkedInJoinUrlString]) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:kLinkedInJoinUrlString]];
        return NO;
    }
    
    NSRange range = [urlString rangeOfString:kLinkedInContinueUrlString];
    if ([[[DataManager sharedDataManager] currentProfile] isConnectedToLInkedIn] && range.location != NSNotFound) {
        [self goToInApp];
        return NO;
    }
    
    // Check if user tapped revoke permission button
    if ([urlString isEqualToString:kLinkedInRevokeUrlString]) {
        if ([[DataManager sharedDataManager] currentProfileIsSet]) {
            [self revokePermissionTapped];
            return NO;
        } else {
            return YES;
        }
    }
    
    [activityIndicator startAnimating];
    
    BOOL requestForCallbackURL = ([urlString rangeOfString:linkedInCallbackURL].location != NSNotFound);
    if ( requestForCallbackURL )
    {
        BOOL userAllowedAccess = ([urlString rangeOfString:@"user_refused"].location == NSNotFound);
        if ( userAllowedAccess )
        {            
            [self.requestToken setVerifierWithUrl:url];
            [self accessTokenFromProvider];
        }
        else
        {
            [self.navigationController popToRootViewControllerAnimated:NO];
            AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];    
            UIWindow *currentWindow = self.view.window;
            [UIView transitionWithView:currentWindow duration:0.5 options: UIViewAnimationOptionTransitionFlipFromRight animations:^{
                currentWindow.rootViewController = appDelegate.tabBarController;
            } completion:nil];
            
            [appDelegate.tabBarController setSelectedIndex:0];
        }
    }
    
	return YES;
    ;}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    [activityIndicator stopAnimating];
}

- (void)accessTokenFromProvider
{ 
    OAMutableURLRequest *request = 
    [[[OAMutableURLRequest alloc] initWithURL:accessTokenURL
                                     consumer:consumer
                                        token:self.requestToken   
                                     callback:nil
                            signatureProvider:nil] autorelease];
    
    [request setHTTPMethod:@"POST"];
    accessTokenFetcher = [[OADataFetcher alloc] init];
    [accessTokenFetcher fetchDataWithRequest:request
                                    delegate:self
                           didFinishSelector:@selector(accessTokenResult:didFinish:)
                             didFailSelector:@selector(accessTokenResult:didFail:)];    
}

- (void)accessTokenResult:(OAServiceTicket *)ticket didFinish:(NSData *)data 
{
    NSString *responseBody = [[NSString alloc] initWithData:data
                                                   encoding:NSUTF8StringEncoding];
    
    BOOL problem = ([responseBody rangeOfString:@"oauth_problem"].location != NSNotFound);
    if ( problem )
    {
        NSLog(@"Request access token failed.");
        NSLog(@"%@",responseBody);
        [self showConnectionErrorAlert];
    }
    else
    {
        //Getting linkedIn oauth token and oauth token secret
        NSDictionary *accessTokenDict = [Utilities parseQueryString:responseBody];
        [self.profile setLinkedInOAuthToken:[accessTokenDict objectForKey:kOAuthTokenKey]];	
        [self.profile setLinkedInOAuthTokenSecret:[accessTokenDict objectForKey:kOAuthTokenSecretKey]];	
        self.accessToken = [[[OAToken alloc] initWithHTTPResponseBody:responseBody] autorelease];	
        [self.accessToken storeInUserDefaultsWithServiceProviderName:@"LinkedIn" prefix:nil];
        [self linkedInProfileCall];
    }
    [responseBody release];
}

- (void)accessTokenResult:(OAServiceTicket *)ticket didFail:(NSData *)error
{
    NSLog(@"%@",[error description]);
    [self showConnectionErrorAlert];
}

- (void)showActivityOverlay
{
    if (!activityOverlayView.window) {
        activityOverlayView.frame = [[UIScreen mainScreen] applicationFrame];
        [self.navigationController.view addSubview:activityOverlayView];
    }
}

- (void)hideActivityOverlay
{
    [activityOverlayView removeFromSuperview];
}

- (void)linkedInProfileCall
{
    [self showActivityOverlay];
    
    linkedInDataFetcher = [[LinkedInDataFetcher alloc] initWithConsumer:consumer accessToken:self.accessToken];
    linkedInDataFetcher.delegate = self;
    [linkedInDataFetcher requestProfile];
}

- (BOOL)profileIsValid:(NSDictionary *)aProfileDict
{
    BOOL profileIsValid = NO;
    
    // Let's assume that profile if valid if it has a title
    id title = [aProfileDict objectForKey:@"title"];
    if ([title isKindOfClass:[NSString class]] && ![Utilities stringIsEmpty:title]) {
        profileIsValid = YES;
    }
    
    return profileIsValid;
}

- (void)goToPrivateInfoWithProfile:(Profile *)aProfile
{
    AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    aProfile.apn_token = appDelegate.apnTokeString;
    NSDictionary *profileFields = [NSDictionary dictionaryWithObjectsAndKeys:
                                   aProfile.linkedInId, @"linkedin_id",
                                   aProfile.deviceId, @"device_id",
                                   aProfile.linkedInOAuthToken, @"linkedin_auth_token",
                                   aProfile.linkedInOAuthTokenSecret, @"linkedin_oauth_token_secret",
                                   [Utilities UDID], @"udid", 
                                   appDelegate.apnTokeString, @"apn_token",
                                   nil];
    
    [[CanWeNetworkAPIClient sharedClient] addBaseCredentials];
    [[CanWeNetworkAPIClient sharedClient] postMethod:kProfileAPI parameters:profileFields xtimes:[NSNumber numberWithInt:0] block:^(NSDictionary *records) {
        if ([records objectForKey:@"id"] || [[records objectForKey:@"status"] isEqualToNumber:[NSNumber numberWithInt:kDuplicateProfileStatus]]) {
            NSDictionary *loginCredentials = [NSDictionary dictionaryWithObjectsAndKeys:
                                              [Utilities UDID], @"udid",
                                              aProfile.linkedInId, @"linkedin_id",
                                              aProfile.linkedInOAuthToken, @"linkedin_oauth_token",
                                              aProfile.linkedInOAuthTokenSecret, @"linkedin_oauth_token_secret",
                                              nil];
            
            aProfile.id = [records objectForKey:@"id"];
            [[CanWeNetworkAPIClient sharedClient] postMethod:kLoginAPI parameters:loginCredentials xtimes:[NSNumber numberWithInt:0] block:^(NSDictionary *response) {    
                if ([response objectForKey:@"profile_info"] && [response objectForKey:@"udid_info"]) {
                    NSDictionary *aProfileDict = [response objectForKey:@"profile_info"];
                    NSDictionary *anUdidInfoDict = [response objectForKey:@"udid_info"];
                    if ([self profileIsValid:aProfileDict] ) {
                        // Profile is valid, so we can map it into managed object
                        NSArray *profileArray = [NSArray arrayWithObject:aProfileDict];
                        NSArray *mappedObjects = [[DataManager sharedDataManager] mapObjectsFromArray:profileArray toClass:[Profile class]];
                        Profile *mappedProfile = [mappedObjects lastObject];
                        
                        // And set it as current profile and switch to inApp
                        if (mappedProfile != nil) {
                            NSNumber *udidObjectId = [anUdidInfoDict objectForKey:@"id"];
                            NSString *udidObjectIdString = [udidObjectId stringValue];
                            NSString *login = [NSString stringWithFormat:@"%@:%@", aProfile.linkedInId, udidObjectIdString];
                            
                            NSLog(@"Login: %@, Password: %@", login, aProfile.linkedInOAuthToken);
                            [[CanWeNetworkAPIClient sharedClient] setAuthenticationChallenge:login password:aProfile.linkedInOAuthToken linkedIn:YES];
                            [Utilities tryToPerformSelector:@selector(loginViewController:didLoginWithProfile:) withObject:self withObject:mappedProfile onTarget:self.delegate];
                            [self goToInApp];
                            //get udid_info
                            AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
                            if([[anUdidInfoDict objectForKey:@"apn_token"] isKindOfClass:[NSString class]]){
                                if(![[anUdidInfoDict objectForKey:@"apn_token"] isEqualToString:appDelegate.apnTokeString]){
                                    appDelegate.shouldUpdateApn = YES;
                                }else{
                                    appDelegate.shouldUpdateApn = NO;
                                }
                            }
                        }
                    } else {
                        // Profile is invalid, so we have to go to onboarding process
                        [[DataManager sharedDataManager] deleteDuplicatesOfProfile:aProfile];
                        NSNumber *udidObjectId = [anUdidInfoDict objectForKey:@"id"];
                        NSString *udidObjectIdString = [udidObjectId stringValue];
                        NSString *login = [NSString stringWithFormat:@"%@:%@", aProfile.linkedInId, udidObjectIdString];
                        
                        NSLog(@"Login: %@, Password: %@", login, aProfile.linkedInOAuthToken);
                        [[CanWeNetworkAPIClient sharedClient] setAuthenticationChallenge:login password:aProfile.linkedInOAuthToken linkedIn:YES];
                        PrivateInfoViewController *pivc = [[PrivateInfoViewController alloc] initWithProfile:aProfile];
                        [self.navigationController pushViewController:pivc animated:YES];
                        [pivc release];
                    }
                } else {
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil message:@"Connection Error" delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
                    [alert show];
                    [alert release];
                }
            }];
        } else {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil message:@"Connection Error" delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
            [alert show];
            [alert release];
        }
    }];
}

- (void)saveProfileAndCloseLoginView:(Profile *)aProfile
{
    NSString *pictureUrl = self.profile.pictureUrl;
    if (pictureUrl.length > 0) {
        UIImage *image = [[CacheMan sharedCacheMan] cachedImageForURL:[NSURL URLWithString:pictureUrl] cacheName:nil placeholderImage:nil];
        NSData* imageData = UIImageJPEGRepresentation(image, 1.0);
        NSString *uniqueString = [NSString stringWithFormat:@"%@.jpg", [Utilities stringWithUUID]];
        self.profile.pictureUrl = uniqueString;
        NSURL *pictureUrl = [NSURL URLWithString:uniqueString];
        [[CacheMan sharedCacheMan] cacheImageData:imageData forURL:pictureUrl cacheName:nil];
    }
    
    [[DataManager sharedDataManager] postProfileToTheServer:aProfile block: ^(NSDictionary *records) {
        if(records && [records objectForKey:@"status"]){
            [self.navigationController popToRootViewControllerAnimated:NO];
            AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];    
            UIWindow *currentWindow = self.view.window;
            [UIView transitionWithView:currentWindow duration:0.5 options: UIViewAnimationOptionTransitionFlipFromRight animations:^{
                currentWindow.rootViewController = appDelegate.tabBarController;
            } completion:nil];
            
        }else{
            aProfile.linkedInId = @"";
        }
    }];
    
    [self hideActivityOverlay]; 
    [[DataManager sharedDataManager] save];
}

- (void)backButtonTapped:(id)sender 
{
    [self.navigationController popToRootViewControllerAnimated:NO];
    
    AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];    
    UIWindow *currentWindow = self.view.window;
    [UIView transitionWithView:currentWindow duration:0.5 options: UIViewAnimationOptionTransitionFlipFromRight animations:^{
        currentWindow.rootViewController = appDelegate.tabBarController;
    } completion:nil];
}

- (void)initLinkedInApi
{
    apikey = linkedInAPIkey;
    secretkey = linkedInSecretKey;
    
    consumer = [[OAConsumer alloc] initWithKey:apikey
                                        secret:secretkey
                                         realm:@"http://api.linkedin.com/"];
    
    requestTokenURLString = @"https://api.linkedin.com/uas/oauth/requestToken";
    accessTokenURLString = @"https://api.linkedin.com/uas/oauth/accessToken";
    userLoginURLString = @"https://www.linkedin.com/uas/oauth/authorize";    
    linkedInCallbackURL = @"hdlinked://linkedin/oauth";
    
    requestTokenURL = [[NSURL URLWithString:requestTokenURLString] retain];
    accessTokenURL = [[NSURL URLWithString:accessTokenURLString] retain];
    userLoginURL = [[NSURL URLWithString:userLoginURLString] retain];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self initLinkedInApi];
    
    [self.navigationController setNavigationBarHidden:NO]; 
    
    UIBarButtonItem *backButtonItem = [[UIBarButtonItem alloc] initWithCustomView:backButton];
    [backButton addTarget:self action:@selector(backButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self navigationItem].leftBarButtonItem = backButtonItem;
    [backButtonItem release];
    
    activityIndicator = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
    activityIndicator.hidesWhenStopped = YES;
    UIBarButtonItem * activityIndicatorItem = [[UIBarButtonItem alloc] initWithCustomView:activityIndicator];
    [self navigationItem].rightBarButtonItem = activityIndicatorItem;
    [activityIndicatorItem release];
}

- (void)viewDidAppear:(BOOL)animated
{
    [self requestTokenFromProvider];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        
    }
    return self;
}

- (id)initWithProfile:(Profile *)aProfile
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = @"Login to LinkedIn";
        profile = [aProfile retain];
    }
    return self;
}

- (void)releaseOutlets
{
    [webView release];
    webView = nil;
    [backButton release];
    backButton = nil;
    [activityIndicator release];
    activityIndicator = nil;
    [activityOverlayView release];
    activityOverlayView = nil;
}

- (void)dealloc
{
    [self releaseOutlets];
    self.delegate = nil;
    [requestTokenFetcher cancelRequest];
    [requestTokenFetcher release];
    [accessTokenFetcher cancelRequest];
    [accessTokenFetcher release];
    [linkedInDataFetcher cancelRequest];
    [linkedInDataFetcher release];
    [self setProfile:nil];
    [super dealloc];
}

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidUnload
{
    [self releaseOutlets];
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait ||
            interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown);
}

- (void)startUpdatingProfile:(Profile *)aProfile
{
    [[LinkedInProfileUpdateManager sharedUpdateManager] setProfileDataFetcher:linkedInDataFetcher];
    [[LinkedInProfileUpdateManager sharedUpdateManager] setProfile:aProfile];
    [[LinkedInProfileUpdateManager sharedUpdateManager] setUpdateInterval:kLinkedInProfileUpdateInterval];
    [[LinkedInProfileUpdateManager sharedUpdateManager] startProfileUpdates];
}

#pragma mark - LinkedInDataFetcherDelegate

- (void)linkedInDataFetcher:(LinkedInDataFetcher *)fetcher didLoadProfile:(NSDictionary *)aProfileDict
{
    self.profileDict = aProfileDict;
    
    Profile *linkedInProfile = [LinkedInProfileParser updateProfile:self.profile withProfileDict:profileDict];
    fetcher.delegate = nil;
    
    [self startUpdatingProfile:linkedInProfile];
    
    [self hideActivityOverlay];
    
    BOOL currentProfileIsSet = [[DataManager sharedDataManager] currentProfileIsSet];
    if (currentProfileIsSet) {
        [self saveProfileAndCloseLoginView:linkedInProfile];
    } else  {
        [self goToPrivateInfoWithProfile:linkedInProfile];
    }
}

- (void)linkedInDataFetcher:(LinkedInDataFetcher *)fetcher didFailLoadingProfileWithError:(NSData *)error
{
    fetcher.delegate = nil;
    [self hideActivityOverlay];
    [self showProfileErrorAlert];
    NSLog(@"%@",[error description]);
}

@end
