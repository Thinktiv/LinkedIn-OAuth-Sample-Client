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
#import "PublicInfo.h"
#import "Skill.h"
#import "Industry.h"
#import "Experience.h"
#import "Education.h"
#import "PrivateInfoViewController.h"
#import "LinkedInProfileParser.h"
#import "LinkedInProfileUpdateManager.h"

@implementation OAuthLoginView

@synthesize requestToken, accessToken, profileDict, profile, consumer;

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

- (BOOL)webView:(UIWebView*)webView shouldStartLoadWithRequest:(NSURLRequest*)request navigationType:(UIWebViewNavigationType)navigationType 
{
	NSURL *url = request.URL;
	NSString *urlString = url.absoluteString;
    
    if ([urlString isEqualToString:kLinkedInJoinUrlString]) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:kLinkedInJoinUrlString]];
        return NO;
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
}

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
        self.accessToken = [[[OAToken alloc] initWithHTTPResponseBody:responseBody] autorelease];
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

- (void)goToPrivateInfoWithProfile:(Profile *)aProfile
{
    PrivateInfoViewController *pivc = [[PrivateInfoViewController alloc] initWithProfile:aProfile];
    [self.navigationController pushViewController:pivc animated:YES];
    [pivc release];
}

- (void)saveProfileAndCloseLoginView
{
    [[DataManager sharedDataManager] save];
    
    [self.navigationController popToRootViewControllerAnimated:NO];
    AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];    
    UIWindow *currentWindow = self.view.window;
    [UIView transitionWithView:currentWindow duration:0.5 options: UIViewAnimationOptionTransitionFlipFromRight animations:^{
        currentWindow.rootViewController = appDelegate.tabBarController;
    } completion:nil];
}

- (void)backButtonTapped:(id)sender {
    [self.navigationController popToRootViewControllerAnimated:NO];
    
    AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];    
    UIWindow *currentWindow = self.view.window;
    [UIView transitionWithView:currentWindow duration:0.5 options: UIViewAnimationOptionTransitionFlipFromRight animations:^{
        currentWindow.rootViewController = appDelegate.tabBarController;
    } completion:nil];
}

- (void)initLinkedInApi
{
    apikey = @"pr8muxsq7t0z";
    secretkey = @"NljvX8ge1CFsBSJY";   
    
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
        [self saveProfileAndCloseLoginView];
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
