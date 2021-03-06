
#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import <JavaScriptCore/JavaScriptCore.h>

#import "UAWebViewDelegate.h"
#import "UAirship.h"
#import "UAConfig.h"
#import "UAUser.h"
#import "UAInboxMessage.h"
#import "UAUtils.h"
#import "UAInbox.h"
#import "UAInboxMessageList.h"

@interface UAWebViewDelegateTest : XCTestCase

@property(nonatomic, strong) UAWebViewDelegate *delegate;
@property(nonatomic, strong) id mockWebView;
@property(nonatomic, strong) id mockForwardDelegate;
@property(nonatomic, strong) id mockContentWindow;

@property (strong, nonatomic) id mockUIDevice;
@property (strong, nonatomic) id mockUAUser;
@property (strong, nonatomic) id mockAirship;
@property (nonatomic, strong) id mockMessageList;
@property (nonatomic, strong) id mockInbox;
@property (nonatomic, strong) JSContext *jsc;

@end


@implementation UAWebViewDelegateTest

- (void)setUp {
    [super setUp];
    self.delegate = [[UAWebViewDelegate alloc] init];
    self.mockForwardDelegate = [OCMockObject niceMockForProtocol:@protocol(UIWebViewDelegate)];
    self.delegate.forwardDelegate = self.mockForwardDelegate;

    self.mockContentWindow = [OCMockObject niceMockForProtocol:@protocol(UARichContentWindow)];
    self.delegate.richContentWindow = self.mockContentWindow;

    // Mock web view
    self.mockWebView = [OCMockObject niceMockForClass:[UIWebView class]];

    // Mock UAUser
    self.mockUAUser = [OCMockObject niceMockForClass:[UAUser class]];
    [[[self.mockUAUser stub] andReturn:self.mockUAUser] defaultUser];

    // Mock UIDevice
    self.mockUIDevice = [OCMockObject niceMockForClass:[UIDevice class]];
    [[[self.mockUIDevice stub] andReturn:self.mockUIDevice] currentDevice];

    // Mock Airship
    self.mockAirship = [OCMockObject niceMockForClass:[UAirship class]];
    [[[self.mockAirship stub] andReturn:self.mockAirship] shared];

    // Set an actual whitelist
    UAWhitelist *whitelist = [UAWhitelist whitelistWithConfig:[UAConfig defaultConfig]];
    [[[self.mockAirship stub] andReturn:whitelist] whitelist];

    // Mock the inbox and message list
    self.mockInbox = [OCMockObject niceMockForClass:[UAInbox class]];
    self.mockMessageList = [OCMockObject niceMockForClass:[UAInboxMessageList class]];
    [[[self.mockInbox stub] andReturn:self.mockInbox] shared];
    [[[self.mockInbox stub] andReturn:self.mockMessageList] messageList];

    // Set up a Javascript environment
    self.jsc = [[JSContext alloc] initWithVirtualMachine:[[JSVirtualMachine alloc] init]];
    [self.jsc evaluateScript:@"window = {}"];
}

- (void)tearDown {
    [self.mockAirship stopMocking];
    [self.mockWebView stopMocking];
    [self.mockUIDevice stopMocking];
    [self.mockUAUser stopMocking];
    [self.mockForwardDelegate stopMocking];
    [self.mockContentWindow stopMocking];

    [self.mockMessageList stopMocking];
    [self.mockInbox stopMocking];

    [super tearDown];
}

/**
 * Test webViewDidStartLoad: forwards its message to the forwardDelegate.
 */
- (void)testDidStartLoadForwardDelegate {
    [[self.mockForwardDelegate expect] webViewDidStartLoad:self.mockWebView];
    [self.delegate webViewDidStartLoad:self.mockWebView];
    [self.mockForwardDelegate verify];
}

/**
 * Test webView:didFailLoadWithError: forwards its message to the forwardDelegate.
 */
- (void)testDidFailLoadForwardDelegate {
    NSError *err = [NSError errorWithDomain:@"wat" code:0 userInfo:nil];
    [[self.mockForwardDelegate expect] webView:self.mockWebView didFailLoadWithError:err];
    [self.delegate webView:self.mockWebView didFailLoadWithError:err];
    [self.mockForwardDelegate verify];
}

/**
 * Test shouldStartLoadWithRequest:navigationType: forwards its message to the forwardDelegate.
 */
- (void)testShouldStartLoadForwardDelegate {
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://urbanairship.com"]];
    [[self.mockForwardDelegate expect] webView:self.mockWebView shouldStartLoadWithRequest:request navigationType:UIWebViewNavigationTypeOther];
    [self.delegate webView:self.mockWebView shouldStartLoadWithRequest:request navigationType:UIWebViewNavigationTypeOther];
    [self.mockForwardDelegate verify];
}

/**
 * Test webViewDidFinishLoad: forwards its message to the forwardDelegate.
 */
- (void)testDidFinishLoadForwardDelegate {
    [[self.mockForwardDelegate expect] webViewDidFinishLoad:self.mockWebView];
    [self.delegate webViewDidFinishLoad:self.mockWebView];
    [self.mockForwardDelegate verify];
}

/**
 * Test closeWebView:animated: forwards its message to the richContentWindow.
 */
- (void)testCloseWebView {
    [[self.mockContentWindow expect] closeWebView:self.mockWebView animated:YES];
    [self.delegate closeWebView:self.mockWebView animated:YES];
    [self.mockForwardDelegate verify];
}

/**
 * Test webViewDidFinishLoad: injects the UA Javascript interface.
 */
- (void)testDidFinishPopulateJavascriptEnvironment {
    [[[self.mockUAUser stub] andReturn:@"user name"] username];
    [[[self.mockUIDevice stub] andReturn:@"device model"] model];

    __block NSString *js;

    // Capture the js environment string
    [[[self.mockWebView stub] andDo:^(NSInvocation *invocation) {
        [invocation getArgument:&js atIndex:2];
        [invocation setReturnValue:&js];
    }] stringByEvaluatingJavaScriptFromString:[OCMArg any]];

    // Any https://*.urbanairship.com/* urls are white listed
    NSURL *url = [NSURL URLWithString:@"https://foo.urbanairship.com/whatever.html"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.mainDocumentURL = url;
    [[[self.mockWebView stub] andReturn:request] request];

    // Notifiy the web view is finished loading the main frame
    [self.delegate webViewDidFinishLoad:self.mockWebView];

    XCTAssertNotNil(js, "Javascript environment was not populated");

    [self.jsc evaluateScript:js];

    // Verify device model
    XCTAssertEqualObjects(@"device model", [self.jsc evaluateScript:@"UAirship.devicemodel"].toString);
    XCTAssertEqualObjects(@"device model", [self.jsc evaluateScript:@"UAirship.getDeviceModel()"].toString);

    // Verify user id
    XCTAssertEqualObjects(@"user name", [self.jsc evaluateScript:@"UAirship.userID"].toString);
    XCTAssertEqualObjects(@"user name", [self.jsc evaluateScript:@"UAirship.getUserId()"].toString);

    // Verify message id is null
    XCTAssertTrue([self.jsc evaluateScript:@"UAirship.getMessageId()"].isNull);
    XCTAssertTrue([self.jsc evaluateScript:@"UAirship.messageID"].isNull);

    // Verify message title is null
    XCTAssertTrue([self.jsc evaluateScript:@"UAirship.getMessageTitle()"].isNull);
    XCTAssertTrue([self.jsc evaluateScript:@"UAirship.messageTitle"].isNull);

    // Verify message send date is null
    XCTAssertTrue([self.jsc evaluateScript:@"UAirship.getMessageSentDate()"].isNull);
    XCTAssertTrue([self.jsc evaluateScript:@"UAirship.messageSentDate"].isNull);

    // Verify message send date ms is -1
    XCTAssertEqualObjects(@-1, [self.jsc evaluateScript:@"UAirship.getMessageSentDateMS()"].toNumber);
    XCTAssertEqualObjects(@-1, [self.jsc evaluateScript:@"UAirship.messageSentDateMS"].toNumber);


    // Verify native bridge methods are not undefined
    XCTAssertFalse([self.jsc evaluateScript:@"UAirship.delegateCallURL"].isUndefined);
    XCTAssertFalse([self.jsc evaluateScript:@"UAirship.invoke"].isUndefined);
    XCTAssertFalse([self.jsc evaluateScript:@"UAirship.runAction"].isUndefined);
    XCTAssertFalse([self.jsc evaluateScript:@"UAirship.finishAction"].isUndefined);
}

/**
 * Test webViewDidFinishLoad: injects the UA Javascript interface with the
 * inbox message information if the web view's main document url points to
 * a message's body URL.
 */
- (void)testDidFinishPopulateJavascriptEnvironmentWithInboxMessage {

    NSDate *messageSent = [NSDate date];
    id message = [OCMockObject niceMockForClass:[UAInboxMessage class]];
    [[[message stub] andReturn:@"messageID"] messageID];
    [[[message stub] andReturn:@"messageTitle"] title];
    [[[message stub] andReturn:messageSent] messageSent];
    [[[message stub] andReturnValue:@(YES)] unread];

    __block NSString *js;

    // Capture the js environment string
    [[[self.mockWebView stub] andDo:^(NSInvocation *invocation) {
        [invocation getArgument:&js atIndex:2];
        [invocation setReturnValue:&js];
    }] stringByEvaluatingJavaScriptFromString:[OCMArg any]];

    NSURL *url = [NSURL URLWithString:@"https://foo.urbanairship.com/whatever.html"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.mainDocumentURL = url;


    // Associate the URL with the mock message
    [[[self.mockMessageList stub] andReturn:message] messageForBodyURL:url];

    [[[self.mockWebView stub] andReturn:request] request];

    [self.delegate webViewDidFinishLoad:self.mockWebView];

    XCTAssertNotNil(js, "Javascript environment was not populated");

    [self.jsc evaluateScript:js];

    // Verify message id
    XCTAssertEqualObjects(@"messageID", [self.jsc evaluateScript:@"UAirship.getMessageId()"].toString);

    // Verify message title
    XCTAssertEqualObjects(@"messageTitle", [self.jsc evaluateScript:@"UAirship.getMessageTitle()"].toString);

    // Verify message send date
    XCTAssertEqualObjects([[UAUtils ISODateFormatterUTC] stringFromDate:messageSent], [self.jsc evaluateScript:@"UAirship.getMessageSentDate()"].toString);

    // Verify message send date ms
    double milliseconds = [messageSent timeIntervalSince1970] * 1000;
    XCTAssertEqualWithAccuracy(milliseconds, [self.jsc evaluateScript:@"UAirship.getMessageSentDateMS()"].toDouble, 0.001);

    [message stopMocking];
}

/**
 * Test that webViewDidFinishLoad: does not load the JS environment when the URL is not whitelisted.
 */
- (void)testDidFinishNotWhitelitsed {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://foo.notwhitelisted.com/whatever.html"]];
    request.mainDocumentURL = request.URL;

    [[[self.mockWebView stub] andReturn:request] request];

    // Capture the js environment string
    [[[self.mockWebView stub] andDo:^(NSInvocation *invocation) {
        XCTFail(@"No JS should have been injected");
    }] stringByEvaluatingJavaScriptFromString:[OCMArg any]];

    [self.delegate webViewDidFinishLoad:self.mockWebView];
}

/**
 * Test that webViewDidFinishLoad: only popluates the JS interface once even if called
 * multiple time.
 */
- (void)testDidFinishCalledMultipleTimes {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://foo.urbanairship.com/whatever.html"]];
    request.mainDocumentURL = request.URL;

    [[[self.mockWebView stub] andReturn:request] request];

    // Expect the interface to be injected.
    [[self.mockWebView expect] stringByEvaluatingJavaScriptFromString:[OCMArg any]];

    [self.delegate webViewDidFinishLoad:self.mockWebView];
    [self.mockWebView verify];

    // Verify it does not inject any JS interface a second time
    [[self.mockWebView reject] stringByEvaluatingJavaScriptFromString:[OCMArg any]];
    [self.delegate webViewDidFinishLoad:self.mockWebView];
    [self.mockWebView verify];
}

@end
