//
//  BayeuxClient.m
//  Pods
//
//  Created by Robert Matcuk on 5/9/14.
//
//

#import "BayeuxClient.h"

#if !__has_feature(objc_subscripting)
    #error BayeuxClient must be compiled with Apple's LLVM Compiler v4.0+ (xcode 4.4+) or the open source LLVM compiler v3.1+.
#endif
#if !__has_feature(objc_arc)
    #error BayeuxClient must be compiled with ARC enabled.
#endif

#ifdef DEBUG
    #define LOG(...) NSLog(__VA_ARGS__)
#else
    #define LOG(...)
#endif


typedef enum {
    ADVICE_RETRY,
    ADVICE_HANDSHAKE,
    ADVICE_NONE
} BayeuxClientAdviceReconnect;


@interface BayeuxClient ()

@property SRWebSocket *webSocket;
@property NSString *clientId;
@property (readonly) NSMutableDictionary *subscriptions;
@property (readonly) NSMutableArray *extensions;
@property (readonly) BayeuxClientAdviceReconnect adviceReconnect;
@property (readonly) NSTimeInterval adviceInterval;


- (void)sendBayeuxHandshake;
- (void)sendBayeuxConnect;
- (void)sendBayeuxSubscribeToChannel:(NSString *)channel;
- (void)sendBayeuxUnsubscribeFromChannel:(NSString *)channel;
- (void)sendBayeuxDisconnect;

- (NSError *)buildErrorFromBayeuxMessage:(NSDictionary *)message withDescription:(NSString *)description;
- (void)handleBayeuxError:(NSDictionary *)message withDescription:(NSString *)description;

- (void)connectWebSocket;
- (void)writeMessageToWebSocket:(NSDictionary *)message;
- (void)setupPingTimer;
- (void)pingWebSocket;
- (void)disconnectWebSocket;

@end


@implementation BayeuxClient

- (id)init
{
    if (self = [super init]) {
        _subscriptions = [[NSMutableDictionary alloc] init];
        _extensions = [[NSMutableArray alloc] init];
        _adviceReconnect = ADVICE_RETRY;
        _adviceInterval = 0.0;
    }
    return self;
}

- (instancetype)initWithURLString:(NSString *)url
{
    return [self initWithURL:[NSURL URLWithString:url]];
}

- (instancetype)initWithURL:(NSURL *)url
{
    if (self = [self init]) {
        _url = url;
    }
    return self;
}

- (void)connect
{
    if (self.isConnected)
        return;
    
    [self connectWebSocket];
}

- (void)subscribeToChannel:(NSString *)channel
{
    if (!channel) return;
    
    BOOL needToSubscribe = YES;
    NSNumber *numberOfSubscriptions = self.subscriptions[channel];
    if (numberOfSubscriptions) {
        needToSubscribe = NO;
        numberOfSubscriptions = @(numberOfSubscriptions.intValue + 1);
    } else {
        numberOfSubscriptions = @1;
    }
    self.subscriptions[channel] = numberOfSubscriptions;
    
    if (self.isConnected && needToSubscribe)
        [self sendBayeuxSubscribeToChannel:channel];
}

- (void)unsubscribeFromChannel:(NSString *)channel
{
    if (!channel) return;
    
    NSNumber *numberOfSubscriptions = self.subscriptions[channel];
    if (numberOfSubscriptions) {
        numberOfSubscriptions = @(numberOfSubscriptions.intValue - 1);
        if (numberOfSubscriptions.intValue <= 0 && self.isConnected) {
            [self.subscriptions removeObjectForKey:channel];
            [self sendBayeuxUnsubscribeFromChannel:channel];
        }
    }
}

- (void)addExtension:(NSObject<BayeuxClientExtension> *)extension
{
    [self.extensions addObject:extension];
}

- (void)removeExtension:(NSObject<BayeuxClientExtension> *)extension
{
    [self.extensions removeObject:extension];
}

- (void)disconnect
{
    if (self.isConnected)
        [self sendBayeuxDisconnect];
}


#pragma mark - Bayeux Protocol

- (void)sendBayeuxHandshake
{
    if (self.adviceReconnect == ADVICE_NONE) {
        [self disconnectWebSocket];
        return;
    }
    
    NSDictionary *message = @{@"channel":                  @"/meta/handshake",
                              @"version":                  @"1.0",
                              @"minimumVersion":           @"1.0beta",
                              @"supportedConnectionTypes": @[@"websocket"]};
    LOG(@"Sending Bayeux Handshake...");
    [self writeMessageToWebSocket:message];
}

- (void)sendBayeuxConnect
{
    NSDictionary *message = @{@"channel":        @"/meta/connect",
                              @"clientId":       self.clientId,
                              @"connectionType": @"websocket"};
    LOG(@"Sending Bayeux Connect...");
    [self writeMessageToWebSocket:message];
}

- (void)sendBayeuxSubscribeToChannel:(NSString *)channel
{
    NSDictionary *message = @{@"channel":      @"/meta/subscribe",
                              @"clientId":     self.clientId,
                              @"subscription": channel};
    LOG(@"Sending Bayeux Subscribe...");
    [self writeMessageToWebSocket:message];
}

- (void)sendBayeuxUnsubscribeFromChannel:(NSString *)channel
{
    NSDictionary *message = @{@"channel":      @"/meta/unsubscribe",
                              @"clientId":     self.clientId,
                              @"subscription": channel};
    LOG(@"Sending Bayeux Unsubscribe...");
    [self writeMessageToWebSocket:message];
}

- (void)sendBayeuxDisconnect
{
    NSDictionary *message = @{@"channel":  @"/meta/disconnect",
                              @"clientId": self.clientId};
    LOG(@"Sending Bayeux Disconnect...");
    [self writeMessageToWebSocket:message];
}

- (NSError *)buildErrorFromBayeuxMessage:(NSDictionary *)message withDescription:(NSString *)description
{
    NSMutableDictionary *errorInfo = [[NSMutableDictionary alloc] init];
    errorInfo[NSLocalizedDescriptionKey] = description;
    
    NSString *errorMessage = message[@"error"];
    NSInteger code = 0;
    if (errorMessage) {
        NSArray *errorComponents = [errorMessage componentsSeparatedByString:@":"];
        if (errorComponents.count > 1) {
            errorInfo[NSLocalizedFailureReasonErrorKey] = errorComponents.lastObject;
            code = [errorComponents[0] integerValue];
        } else {
            errorInfo[NSLocalizedFailureReasonErrorKey] = errorMessage;
        }
    }
    
    return [NSError errorWithDomain:@"com.bmatcuk.BayeuxClient.BayeuxError" code:code userInfo:errorInfo];
}

- (void)handleBayeuxError:(NSDictionary *)message withDescription:(NSString *)description
{
    if ([self.delegate respondsToSelector:@selector(bayeuxClient:failedWithError:)]) {
        NSError *error = [self buildErrorFromBayeuxMessage:message withDescription:description];
        [self.delegate bayeuxClient:self failedWithError:error];
    }
}


#pragma mark - WebSocket Methods

- (void)connectWebSocket
{
    [self disconnectWebSocket];
    
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:self.url];
    self.webSocket = [[SRWebSocket alloc] initWithURLRequest:request];
    self.webSocket.delegate = self;
    [self.webSocket open];
}

- (void)writeMessageToWebSocket:(NSDictionary *)message
{
    if (self.extensions.count > 0) {
        NSMutableDictionary *mutableMessage = [message mutableCopy];
        for (__strong id extension in self.extensions) {
            if ([extension isKindOfClass:[NSValue class]])
                extension = [extension nonretainedObjectValue];
            
            if ([extension respondsToSelector:@selector(bayeuxClient:willSendMessage:)]) {
                if (![extension bayeuxClient:self willSendMessage:mutableMessage])
                    return;
            }
        }
        message = mutableMessage;
    }
    
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:message options:0 error:&error];
    if (error) {
        if ([self.delegate respondsToSelector:@selector(bayeuxClient:failedToSerializeMessage:withError:)])
            [self.delegate bayeuxClient:self failedToSerializeMessage:message withError:error];
    } else {
        NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        [self.webSocket send:json];
    }
}

- (void)setupPingTimer
{
    [self performSelector:@selector(pingWebSocket) withObject:nil afterDelay:(self.adviceInterval / 2.0)];
}

- (void)pingWebSocket
{
    if (self.isConnected) {
        // send an empty array to do nothing, but keep the socket open
        LOG(@"Sending ping...");
        [self.webSocket send:@"[]"];
        [self setupPingTimer];
    }
}

- (void)disconnectWebSocket
{
    _connected = NO;
    self.webSocket.delegate = nil;
    [self.webSocket close];
    self.webSocket = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}


#pragma mark - SRWebSocketDelegate

- (void)webSocketDidOpen:(SRWebSocket *)webSocket
{
    [self sendBayeuxHandshake];
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message
{
    id data = message;
    if ([data isKindOfClass:[NSString class]])
        data = [data dataUsingEncoding:NSUTF8StringEncoding];
    
    NSError *error = nil;
    NSArray *messages = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error) {
        if ([self.delegate respondsToSelector:@selector(bayeuxClient:failedToDeserializeMessage:withError:)])
            [self.delegate bayeuxClient:self failedToDeserializeMessage:message withError:error];
    } else {
        for (__strong NSDictionary *message in messages) {
            
            if (self.extensions.count > 0) {
                NSMutableDictionary *mutableMessage = [message mutableCopy];
                for (__strong id extension in self.extensions) {
                    if ([extension isKindOfClass:[NSValue class]])
                        extension = [extension nonretainedObjectValue];
                    
                    if ([extension respondsToSelector:@selector(bayeuxClient:willReceiveMessage:)]) {
                        if (![extension bayeuxClient:self willReceiveMessage:mutableMessage])
                            continue;
                    }
                }
                message = mutableMessage;
            }
            
            NSDictionary *advice = message[@"advice"];
            if (advice) {
                NSString *reconnect = advice[@"reconnect"];
                if (reconnect) {
                    if ([reconnect isEqualToString:@"retry"])
                        _adviceReconnect = ADVICE_RETRY;
                    else if ([reconnect isEqualToString:@"handshake"])
                        _adviceReconnect = ADVICE_HANDSHAKE;
                    else
                        _adviceReconnect = ADVICE_NONE;
                }
                
                if (advice[@"interval"]) {
                    // interval is in milliseconds - convert to seconds
                    _adviceInterval = [advice[@"interval"] doubleValue] / 1000.0;
                    if (self.adviceInterval <= 0.0)
                        _adviceInterval = 0.0;
                }
                
                if (self.adviceReconnect == ADVICE_HANDSHAKE && self.isConnected) {
                    _connected = NO;
                    _clientId = nil;
                    [NSObject cancelPreviousPerformRequestsWithTarget:self];
                    [self performSelector:@selector(sendBayeuxHandshake) withObject:nil afterDelay:self.adviceInterval];
                }
            }
            
            NSString *channel = message[@"channel"];
            if ([channel hasPrefix:@"/meta/"]) {
                
                // handle "meta" messages
                if ([channel isEqualToString:@"/meta/handshake"]) {
                    
                    // received a handshake response
                    LOG(@"Received Bayeux Handshake Response");
                    if ([message[@"successful"] boolValue]) {
                        self.clientId = message[@"clientId"];
                        _connected = YES;
                        
                        if ([self.delegate respondsToSelector:@selector(bayeuxClientDidConnect:)])
                            [self.delegate bayeuxClientDidConnect:self];
                        
                        [self sendBayeuxConnect];
                        for (NSString *subscription in self.subscriptions.allKeys)
                            [self sendBayeuxSubscribeToChannel:subscription];
                        [self setupPingTimer];
                    }
                    
                } else if ([channel isEqualToString:@"/meta/connect"]) {
                    
                    // received a connect response
                    LOG(@"Received Bayeux Connect Response");
                    if ([message[@"successful"] boolValue]) {
                        // The client must maintain an outstanding connect request
                        _connected = YES;
                        [self sendBayeuxConnect];
                    } else {
                        [self handleBayeuxError:message withDescription:@"Failed to connect to the Bayeux server."];
                    }
                    
                } else if ([channel isEqualToString:@"/meta/disconnect"]) {
                    
                    // received a disconnect response
                    LOG(@"Received Bayeux Disconnect Response");
                    if ([message[@"successful"] boolValue]) {
                        [self disconnectWebSocket];
                        
                        if ([self.delegate respondsToSelector:@selector(bayeuxClientDidDisconnect:)])
                            [self.delegate bayeuxClientDidDisconnect:self];
                    } else {
                        [self handleBayeuxError:message withDescription:@"Failed to disconnect from the Bayeux server."];
                    }
                    
                } else if ([channel isEqualToString:@"/meta/subscribe"]) {
                    
                    // received a subscribe response
                    LOG(@"Received Bayeux Subscribe Response");
                    if ([message[@"successful"] boolValue]) {
                        if ([self.delegate respondsToSelector:@selector(bayeuxClient:subscribedToChannel:)])
                            [self.delegate bayeuxClient:self subscribedToChannel:channel];
                    } else {
                        if ([self.delegate respondsToSelector:@selector(bayeuxClient:failedToSubscribeToChannel:withError:)])
                            [self.delegate bayeuxClient:self failedToSubscribeToChannel:channel withError:[self buildErrorFromBayeuxMessage:message withDescription:@"Failed to subscribe to channel."]];
                    }
                    
                } else if ([channel isEqualToString:@"/meta/unsubscribe"]) {
                    
                    // received an unsubscribe response
                    LOG(@"Received Bayeux Unsubscribe Response");
                    if ([message[@"successful"] boolValue]) {
                        if ([self.delegate respondsToSelector:@selector(bayeuxClient:unsubscribedFromChannel:)])
                            [self.delegate bayeuxClient:self unsubscribedFromChannel:channel];
                    } else {
                        [self handleBayeuxError:message withDescription:@"Failed to unsubscribe from channel."];
                    }
                    
                }
                
            } else {
                
                // non-meta message, ie, something the user subscribed to
                LOG(@"Received message from Bayeux");
                [self.delegate bayeuxClient:self receivedMessage:message fromChannel:channel];
                
            }
            
        }
    }
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error
{
    if ([self.delegate respondsToSelector:@selector(bayeuxClient:failedWithError:)])
        [self.delegate bayeuxClient:self failedWithError:error];
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean
{
    [self disconnectWebSocket];
    if ([self.delegate respondsToSelector:@selector(bayeuxClient:failedWithError:)]) {
        NSDictionary *errorInfo = @{NSLocalizedDescriptionKey: @"The WebSocket encountered an error.",
                                    NSLocalizedFailureReasonErrorKey: reason};
        NSError *error = [NSError errorWithDomain:@"com.bmatcuk.BayeuxClient.WebSocketError" code:code userInfo:errorInfo];
        [self.delegate bayeuxClient:self failedWithError:error];
    }
    if (self.adviceReconnect != ADVICE_NONE)
        [self performSelector:@selector(connectWebSocket) withObject:nil afterDelay:self.adviceInterval];
}

@end
