//
//  AirPlayServiceHTTP.m
//  Connect SDK
//
//  Created by Jeremy White on 5/28/14.
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

#import "AirPlayServiceHTTP.h"
#import "DeviceService.h"
#import "AirPlayService.h"
#import "ConnectError.h"
#import "DeviceServiceReachability.h"
#import "CTGuid.h"
#import "GCDWebServer.h"

#import "CTASIHTTPRequest.h"

@interface AirPlayServiceHTTP () <ServiceCommandDelegate, DeviceServiceReachabilityDelegate>

@property (nonatomic, readonly) UIBackgroundTaskIdentifier backgroundTaskId;
@property (nonatomic, readonly) DeviceServiceReachability *serviceReachability;
@property (nonatomic, readonly) NSString *sessionId;
@property (nonatomic, readonly) NSString *assetId;
@property (nonatomic, readonly) GCDWebServer *subscriptionServer;
@property (nonatomic, readonly) dispatch_queue_t networkingQueue;
@property (nonatomic, readonly) dispatch_queue_t imageProcessingQueue;

@end

@implementation AirPlayServiceHTTP

- (instancetype) initWithAirPlayService:(AirPlayService *)service
{
    self = [super init];

    if (self)
    {
        _service = service;
        _backgroundTaskId = UIBackgroundTaskInvalid;
        _networkingQueue = dispatch_queue_create("com.connectsdk.AirPlayServiceHTTP.Networking", DISPATCH_QUEUE_SERIAL);
        _imageProcessingQueue = dispatch_queue_create("com.connectsdk.AirPlayServiceHTTP.ImageProcessing", DISPATCH_QUEUE_SERIAL);
    }

    return self;
}

#pragma mark - Connection & Reachability

- (void) connect
{
    _sessionId = [[CTGuid randomGuid] stringValue];

    _connected = YES;

    _serviceReachability = [DeviceServiceReachability reachabilityWithTargetURL:self.service.serviceDescription.commandURL];
    _serviceReachability.delegate = self;
    [_serviceReachability start];

    if (self.service.connected && self.service.delegate && [self.service.delegate respondsToSelector:@selector(deviceServiceConnectionSuccess:)])
        dispatch_on_main(^{ [self.service.delegate deviceServiceConnectionSuccess:self.service]; });
}

- (void) disconnect
{
    _sessionId = nil;

    if (self.backgroundTaskId != UIBackgroundTaskInvalid)
    {
        dispatch_async(self.networkingQueue, ^{
            [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTaskId];
            _backgroundTaskId = UIBackgroundTaskInvalid;
        });
    }

    if (_serviceReachability)
        [_serviceReachability stop];

    _connected = NO;
}

- (void) didLoseReachability:(DeviceServiceReachability *)reachability
{
    if (self.connected)
    {
        [self.service disconnect];
        [self disconnect];
    } else
        [_serviceReachability stop];
}

#pragma mark - Command management

- (int) sendCommand:(ServiceCommand *)command withPayload:(id)payload toURL:(NSURL *)URL
{
    CTASIHTTPRequest *request = [CTASIHTTPRequest requestWithURL:command.target];

    if (payload || [command.HTTPMethod isEqualToString:@"POST"] || [command.HTTPMethod isEqualToString:@"PUT"])
    {
        if (payload)
        {
            NSData *payloadData;
            NSString *contentType;

            if ([payload isKindOfClass:[NSString class]])
            {
                NSString *payloadString = (NSString *)payload;
                payloadData = [payloadString dataUsingEncoding:NSUTF8StringEncoding];
                contentType = @"text/parameters";
            } else if ([payload isKindOfClass:[NSDictionary class]])
            {
                NSError *parseError;
                payloadData = [NSPropertyListSerialization dataWithPropertyList:payload format:NSPropertyListBinaryFormat_v1_0 options:0 error:&parseError];

                if (parseError || !payloadData)
                {
                    NSError *error = parseError;

                    if (!error)
                        error = [ConnectError generateErrorWithCode:ConnectStatusCodeError andDetails:@"Error occurred while parsing property list"];

                    if (command.callbackError)
                        dispatch_on_main(^{ command.callbackError(error); });

                    return -1;
                }

                contentType = @"application/x-apple-binary-plist";
            } else if ([payload isKindOfClass:[NSData class]])
            {
                payloadData = payload;
                contentType = @"image/jpeg";
            }

            if (payloadData == nil)
            {
                if (command.callbackError)
                    command.callbackError([ConnectError generateErrorWithCode:ConnectStatusCodeError andDetails:@"Unknown error preparing message to send"]);

                return -1;
            }

            [request addRequestHeader: @"Content-Length" value:[NSString stringWithFormat:@"%i", (unsigned int) [payloadData length]]];
            [request addRequestHeader: @"Content-Type" value:contentType];
            [request addRequestHeader: @"Connection" value:@"Keep-Alive"];
            [request setPostBody:payloadData];
        } else
        {
            [request addRequestHeader: @"Content-Length" value:@"0"];
        }

        DLog(@"[OUT] : %@ \n %@", request.requestHeaders, payload);
    } else
    {
        [request addRequestHeader: @"Content-Length" value:@"0"];

        DLog(@"[OUT] : %@", request.requestHeaders);
    }

    [request setRequestMethod:command.HTTPMethod];

    if (self.sessionId)
        [request addRequestHeader:@"X-Apple-Session-ID" value:self.sessionId];

    if (self.assetId)
        [request addRequestHeader:@"X-Apple-AssetKey" value:self.assetId];

    [request setShouldAttemptPersistentConnection:YES];
    [request setShouldContinueWhenAppEntersBackground:YES];

    [request setCompletionBlock:^{
        if (request.responseStatusCode == 200)
        {
            NSError *xmlError;
            NSMutableDictionary *plist = [NSPropertyListSerialization propertyListWithData:request.responseData options:NSPropertyListImmutable format:NULL error:&xmlError];

            if (xmlError)
            {
                if (command.callbackComplete)
                    dispatch_on_main(^{ command.callbackComplete(request.responseData); });
            } else
            {
                if (plist)
                {
                    if (command.callbackComplete)
                        dispatch_on_main(^{ command.callbackComplete(plist); });
                }
            }
        } else
        {
            if (command.callbackError)
                dispatch_on_main(^{ command.callbackError([ConnectError generateErrorWithCode:request.responseStatusCode andDetails:nil]); });
        }
    }];

    dispatch_async(self.networkingQueue, ^void {
        // this will prevent the connection dropping on background/sleep modes
        if (self.backgroundTaskId == UIBackgroundTaskInvalid)
            _backgroundTaskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:NULL];

        [request startSynchronous];
    });

    return -1;
}

- (int) sendSubscription:(ServiceSubscription *)subscription type:(ServiceSubscriptionType)type payload:(id)payload toURL:(NSURL *)URL withId:(int)callId
{
    return -1;
}

#pragma mark - Media Player

- (id <MediaPlayer>) mediaPlayer
{
    return self;
}

- (CapabilityPriorityLevel) mediaPlayerPriority
{
    return CapabilityPriorityLevelHigh;
}

- (void) displayImage:(NSURL *)imageURL iconURL:(NSURL *)iconURL title:(NSString *)title description:(NSString *)description mimeType:(NSString *)mimeType success:(MediaPlayerDisplaySuccessBlock)success failure:(FailureBlock)failure
{
    _assetId = [[CTGuid randomGuid] stringValue];

    NSString *commandPathComponent = @"photo";
    NSURL *commandURL = [self.service.serviceDescription.commandURL URLByAppendingPathComponent:commandPathComponent];

    ServiceCommand *command = [ServiceCommand commandWithDelegate:self target:commandURL payload:nil];
    command.HTTPMethod = @"POST";
    command.callbackComplete = ^(id responseObject) {
        LaunchSession *launchSession = [LaunchSession launchSessionForAppId:commandPathComponent];
        launchSession.sessionType = LaunchSessionTypeMedia;
        launchSession.service = self.service;
        launchSession.sessionId = self.sessionId;

        if (success)
            dispatch_on_main(^{ success(launchSession, self.service.mediaControl); });
    };

    command.callbackError = failure;

    dispatch_async(self.imageProcessingQueue, ^{
        NSError *downloadError;
        NSData *downloadedImageData = [NSData dataWithContentsOfURL:imageURL options:0 error:&downloadError];

        if (!downloadedImageData || downloadError)
        {
            if (failure)
            {
                if (downloadError)
                    dispatch_on_main(^{ failure(downloadError); });
                else
                    dispatch_on_main(^{ failure([ConnectError generateErrorWithCode:ConnectStatusCodeError andDetails:@"Could not download requested image"]); });
            }

            return;
        }

        NSData *processedImageData;

        if ([imageURL.absoluteString hasSuffix:@"jpg"] || [imageURL.absoluteString hasSuffix:@"jpeg"])
            processedImageData = downloadedImageData;
        else
        {
            UIImage *image = [UIImage imageWithData:downloadedImageData];

            if (image)
            {
                processedImageData = UIImageJPEGRepresentation(image, 1.0);

                if (!processedImageData)
                {
                    if (failure)
                        dispatch_on_main(^{ failure([ConnectError generateErrorWithCode:ConnectStatusCodeError andDetails:@"Could not convert downloaded image to JPEG format"]); });

                    return;
                }
            } else
            {
                if (failure)
                    dispatch_on_main(^{ failure([ConnectError generateErrorWithCode:ConnectStatusCodeError andDetails:@"Could not convert downloaded data to a suitable image format"]); });

                return;
            }
        }

        command.payload = processedImageData;
        [command send];
    });
}

- (void) playMedia:(NSURL *)mediaURL iconURL:(NSURL *)iconURL title:(NSString *)title description:(NSString *)description mimeType:(NSString *)mimeType shouldLoop:(BOOL)shouldLoop success:(MediaPlayerDisplaySuccessBlock)success failure:(FailureBlock)failure
{
    _assetId = [[CTGuid randomGuid] stringValue];

    NSMutableDictionary *plist = [NSMutableDictionary new];
    plist[@"Content-Location"] = mediaURL.absoluteString;
    plist[@"Start-Position"] = @(0.0);

    NSError *parseError;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0 options:0 error:&parseError];

    if (parseError || !plistData)
    {
        NSError *error = parseError;

        if (!error)
            error = [ConnectError generateErrorWithCode:ConnectStatusCodeError andDetails:@"Error occurred while parsing property list"];

        if (failure)
            failure(error);

        return;
    }

    NSString *payload = [NSString stringWithFormat:@"Content-Location: %@\r\nStart-Position: 0.000000", mediaURL.absoluteString];

    NSString *commandPathComponent = @"play";
    NSURL *commandURL = [self.service.serviceDescription.commandURL URLByAppendingPathComponent:commandPathComponent];

    ServiceCommand *command = [ServiceCommand commandWithDelegate:self target:commandURL payload:plist];
    command.HTTPMethod = @"POST";
    command.callbackComplete = ^(id responseObject) {
        LaunchSession *launchSession = [LaunchSession launchSessionForAppId:commandPathComponent];
        launchSession.sessionType = LaunchSessionTypeMedia;
        launchSession.service = self.service;
        launchSession.sessionId = self.sessionId;

        if (success)
            dispatch_on_main(^{ success(launchSession, self.service.mediaControl); });
    };
    command.callbackError = failure;

    [command send];
}

- (void) closeMedia:(LaunchSession *)launchSession success:(SuccessBlock)success failure:(FailureBlock)failure
{
    [self.mediaControl stopWithSuccess:success failure:failure];
}

#pragma mark - Media Control

- (id <MediaControl>) mediaControl
{
    return self;
}

- (CapabilityPriorityLevel) mediaControlPriority
{
    return CapabilityPriorityLevelHigh;
}

- (void) playWithSuccess:(SuccessBlock)success failure:(FailureBlock)failure
{
    NSString *commandPath = [NSString stringWithFormat:@"%@rate?value=1.000000", self.service.serviceDescription.commandURL.absoluteString];
    NSURL *commandURL = [NSURL URLWithString:commandPath];

    ServiceCommand *command = [ServiceCommand commandWithDelegate:self target:commandURL payload:nil];
    command.HTTPMethod = @"POST";
    command.callbackComplete = success;
    command.callbackError = failure;

    [command send];
}

- (void) pauseWithSuccess:(SuccessBlock)success failure:(FailureBlock)failure
{
    NSString *commandPath = [NSString stringWithFormat:@"%@rate?value=0.000000", self.service.serviceDescription.commandURL.absoluteString];
    NSURL *commandURL = [NSURL URLWithString:commandPath];

    ServiceCommand *command = [ServiceCommand commandWithDelegate:self target:commandURL payload:nil];
    command.HTTPMethod = @"POST";
    command.callbackComplete = success;
    command.callbackError = failure;

    [command send];
}

- (void) stopWithSuccess:(SuccessBlock)success failure:(FailureBlock)failure
{
    NSString *commandPathComponent = @"stop";
    NSURL *commandURL = [self.service.serviceDescription.commandURL URLByAppendingPathComponent:commandPathComponent];

    ServiceCommand *command = [ServiceCommand commandWithDelegate:self target:commandURL payload:nil];
    command.HTTPMethod = @"POST";
    command.callbackComplete = ^(id responseObject) {
        _assetId = nil;

        if (success)
            success(responseObject);
    };
    command.callbackError = failure;

    [command send];
}

- (void) rewindWithSuccess:(SuccessBlock)success failure:(FailureBlock)failure
{
    NSString *commandPath = [NSString stringWithFormat:@"%@rate?value=-2.000000", self.service.serviceDescription.commandURL.absoluteString];
    NSURL *commandURL = [NSURL URLWithString:commandPath];

    ServiceCommand *command = [ServiceCommand commandWithDelegate:self target:commandURL payload:nil];
    command.HTTPMethod = @"POST";
    command.callbackComplete = success;
    command.callbackError = failure;

    [command send];
}

- (void) fastForwardWithSuccess:(SuccessBlock)success failure:(FailureBlock)failure
{
    NSString *commandPath = [NSString stringWithFormat:@"%@rate?value=2.000000", self.service.serviceDescription.commandURL.absoluteString];
    NSURL *commandURL = [NSURL URLWithString:commandPath];

    ServiceCommand *command = [ServiceCommand commandWithDelegate:self target:commandURL payload:nil];
    command.HTTPMethod = @"POST";
    command.callbackComplete = success;
    command.callbackError = failure;

    [command send];
}

- (void) getDurationWithSuccess:(MediaDurationSuccessBlock)success failure:(FailureBlock)failure
{
    NSString *commandPathComponent = [NSString stringWithFormat:@"playback-info"];
    NSURL *commandURL = [self.service.serviceDescription.commandURL URLByAppendingPathComponent:commandPathComponent];

    ServiceCommand *command = [ServiceCommand commandWithDelegate:self target:commandURL payload:nil];
    command.HTTPMethod = @"GET";
    command.callbackComplete = ^(id responseObject) {
        NSTimeInterval duration = [responseObject[@"duration"] floatValue];

        if (success)
            success(duration);
    };
    command.callbackError = failure;

    [command send];
}

- (void) getPlayStateWithSuccess:(MediaPlayStateSuccessBlock)success failure:(FailureBlock)failure
{
    NSString *commandPathComponent = [NSString stringWithFormat:@"playback-info"];
    NSURL *commandURL = [self.service.serviceDescription.commandURL URLByAppendingPathComponent:commandPathComponent];

    ServiceCommand *command = [ServiceCommand commandWithDelegate:self target:commandURL payload:nil];
    command.HTTPMethod = @"GET";
    command.callbackComplete = ^(NSDictionary *responseObject) {
        MediaControlPlayState playState = MediaControlPlayStateUnknown;

        if (responseObject.count == 0)
            playState = MediaControlPlayStateFinished;
        else
        {
            int rate = [responseObject[@"rate"] intValue];

            if (rate == 0)
                playState = MediaControlPlayStatePaused;
            else if (rate == 1)
                playState = MediaControlPlayStatePlaying;
        }

        if (success)
            success(playState);
    };
    command.callbackError = failure;

    [command send];
}

- (void) getPositionWithSuccess:(MediaPositionSuccessBlock)success failure:(FailureBlock)failure
{
    NSString *commandPathComponent = [NSString stringWithFormat:@"playback-info"];
    NSURL *commandURL = [self.service.serviceDescription.commandURL URLByAppendingPathComponent:commandPathComponent];

    ServiceCommand *command = [ServiceCommand commandWithDelegate:self target:commandURL payload:nil];
    command.HTTPMethod = @"GET";
    command.callbackComplete = ^(id responseObject) {
        NSTimeInterval position = [responseObject[@"position"] floatValue];

        if (success)
            success(position);
    };
    command.callbackError = failure;

    [command send];
}

- (void) seek:(NSTimeInterval)position success:(SuccessBlock)success failure:(FailureBlock)failure
{
    NSString *commandPath = [NSString stringWithFormat:@"%@scrub?position=%.06f", self.service.serviceDescription.commandURL.absoluteString, position];
    NSURL *commandURL = [NSURL URLWithString:commandPath];

    ServiceCommand *command = [ServiceCommand commandWithDelegate:self target:commandURL payload:nil];
    command.HTTPMethod = @"POST";
    command.callbackComplete = success;
    command.callbackError = failure;

    [command send];
}

- (ServiceSubscription *) subscribePlayStateWithSuccess:(MediaPlayStateSuccessBlock)success failure:(FailureBlock)failure
{
    if (failure)
        failure([ConnectError generateErrorWithCode:ConnectStatusCodeNotSupported andDetails:nil]);

    return nil;
}

@end
