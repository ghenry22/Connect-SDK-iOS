//
//  WebAppLauncher.h
//  Connect SDK
//
//  Created by Jeremy White on 12/16/13.
//  Copyright (c) 2014 LG Electronics.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import <Foundation/Foundation.h>
#import "Capability.h"
#import "LaunchSession.h"
#import "WebAppSession.h"
#import "MediaControl.h"

#define kWebAppLauncherAny @"WebAppLauncher.Any"

#define kWebAppLauncherLaunch @"WebAppLauncher.Launch"
#define kWebAppLauncherLaunchParams @"WebAppLauncher.Launch.Params"
#define kWebAppLauncherMessageSend @"WebAppLauncher.Message.Send"
#define kWebAppLauncherMessageReceive @"WebAppLauncher.Message.Receive"
#define kWebAppLauncherMessageSendJSON @"WebAppLauncher.Message.Send.JSON"
#define kWebAppLauncherMessageReceiveJSON @"WebAppLauncher.Message.Receive.JSON"
#define kWebAppLauncherClose @"WebAppLauncher.Close"

#define kWebAppLauncherCapabilities @[\
    kWebAppLauncherLaunch,\
    kWebAppLauncherLaunchParams,\
    kWebAppLauncherMessageSend,\
    kWebAppLauncherMessageReceive,\
    kWebAppLauncherMessageSendJSON,\
    kWebAppLauncherMessageReceiveJSON,\
    kWebAppLauncherClose\
]

@protocol WebAppLauncher <NSObject>

/*!
 * Success block that is called upon successfully launch of a web app.
 *
 * @param webAppSession Object containing important information about the web app's session. This object is required to perform many functions with the web app, including app-to-app communication, media playback, closing, etc.
 */
typedef void (^ WebAppLaunchSuccessBlock)(WebAppSession *webAppSession);

- (id<WebAppLauncher>) webAppLauncher;
- (CapabilityPriorityLevel) webAppLauncherPriority;

- (void) launchWebApp:(NSString *)webAppId success:(WebAppLaunchSuccessBlock)success failure:(FailureBlock)failure;
- (void) launchWebApp:(NSString *)webAppId params:(NSDictionary *)params success:(WebAppLaunchSuccessBlock)success failure:(FailureBlock)failure;

/*!
 * This method requires pairing on webOS
 */
- (void) launchWebApp:(NSString *)webAppId relaunchIfRunning:(BOOL)relaunchIfRunning success:(WebAppLaunchSuccessBlock)success failure:(FailureBlock)failure;

/*!
 * This method requires pairing on webOS
 */
- (void) launchWebApp:(NSString *)webAppId params:(NSDictionary *)params relaunchIfRunning:(BOOL)relaunchIfRunning success:(WebAppLaunchSuccessBlock)success failure:(FailureBlock)failure;

- (void) joinWebApp:(NSString *)webAppId success:(SuccessBlock)success failure:(FailureBlock)failure;
- (void) closeWebApp:(LaunchSession *)launchSession success:(SuccessBlock)success failure:(FailureBlock)failure;

@end
