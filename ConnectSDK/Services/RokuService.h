//
//  RokuService.h
//  ConnectSDK
//
//  Created by Jeremy White on 2/14/14.
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

#import <ConnectSDK/ConnectSDK.h>
#import "DIALService.h"

enum
{
    RokuKeyCodeHome,
    RokuKeyCodeRewind,
    RokuKeyCodeFastForward,
    RokuKeyCodePlay,
    RokuKeyCodeSelect,
    RokuKeyCodeLeft,
    RokuKeyCodeRight,
    RokuKeyCodeDown,
    RokuKeyCodeUp,
    RokuKeyCodeBack,
    RokuKeyCodeInstantReplay,
    RokuKeyCodeInfo,
    RokuKeyCodeBackspace,
    RokuKeyCodeSearch,
    RokuKeyCodeEnter,
    RokuKeyCodeLiteral
};

// @cond INTERNAL

typedef NSUInteger RokuKeyCode;

#define kRokuKeyCodes @[ @"Home", @"Rev", @"Fwd", @"Play", @"Select", @"Left", @"Right", @"Down", @"Up", @"Back", @"InstantReplay", @"Info", @"Backspace", @"Search", @"Enter", @"Lit_" ]
// @endcond

@interface RokuService : DeviceService <Launcher, MediaPlayer, MediaControl, KeyControl, TextInputControl>

- (void)sendKeyCode:(RokuKeyCode)keyCode success:(SuccessBlock)success failure:(FailureBlock)failure;


/*!
 * Registers an app ID to be checked upon discovery of this device. If the app is found on the target device, the DIALService will gain the "Launcher.<appID>" capability, where <appID> is the value of the appId parameter.
 *
 * This method must be called before starting DiscoveryManager for the first time.
 *
 * @param appId ID of the app to be checked for
 */
+ (void) registerApp:(NSString *)appId;

@end
