//
//  BayeuxClient.h
//  Pods
//
//  Created by Robert Matcuk on 5/9/14.
//
//

#import <Foundation/Foundation.h>
#import "SRWebSocket.h"


#pragma mark - BayeuxClientExtension

@class BayeuxClient;
@protocol BayeuxClientExtension <NSObject>
@optional

/**
 * Hook called just before the BayeuxClient sends a message to the server
 * @param client The BayeuxClient
 * @param message The message that will be sent
 * @return If you return NO, the message will not be sent.
 */
- (BOOL)bayeuxClient:(BayeuxClient *)client willSendMessage:(NSMutableDictionary *)message;

/**
 * Hook called just after a message was received, before it gets sent to the delegate.
 * @param client The BayeuxClient
 * @param message The message that was received
 * @return If you return NO, the message will not be sent to the delegate.
 */
- (BOOL)bayeuxClient:(BayeuxClient *)client willReceiveMessage:(NSMutableDictionary *)message;

@end


#pragma mark - BayeuxClientDelegate

@protocol BayeuxClientDelegate <NSObject>

/**
 * The client received a message.
 * @param client The BayeuxClient
 * @param message The message received
 * @param channel The channel that the message was received on.
 */
- (void)bayeuxClient:(BayeuxClient *)client receivedMessage:(NSDictionary *)message fromChannel:(NSString *)channel;

@optional

/**
 * Called when the client has successfully connected.
 * @param client The BayeuxClient
 */
- (void)bayeuxClientDidConnect:(BayeuxClient *)client;

/**
 * The client successfully subscribed to a channel.
 * @param client The BayeuxClient
 * @param channel The channel that the client successfully subscribed to.
 */
- (void)bayeuxClient:(BayeuxClient *)client subscribedToChannel:(NSString *)channel;

/**
 * The client successfully unsubscribed from a channel.
 * @param client The BayeuxClient
 * @param channel The channel that was unsubscribed.
 */
- (void)bayeuxClient:(BayeuxClient *)client unsubscribedFromChannel:(NSString *)channel;

/**
 * The client published a message.
 * @param client The BayeuxClient
 * @param messageId The unique message ID returned from publishMessage:toChannel:
 * @param channel The channel that the message was published to.
 * @param error If nil, the message was published successfully. Otherwise, information about why the message couldn't be published.
 */
- (void)bayeuxClient:(BayeuxClient *)client publishedMessageId:(NSString *)messageId toChannel:(NSString *)channel error:(NSError *)error;

/**
 * The client failed to subscribe to a channel.
 * @param client The BayeuxClient
 * @param channel The channel that the client attempted to subscribe to.
 * @param error Why the channel could not be subscribed to.
 */
- (void)bayeuxClient:(BayeuxClient *)client failedToSubscribeToChannel:(NSString *)channel withError:(NSError *)error;

/**
 * Called if the client fails to serialize a message.
 * @param client The BayeuxClient
 * @param message The message that failed serialization
 * @param error Information about the error.
 */
- (void)bayeuxClient:(BayeuxClient *)client failedToSerializeMessage:(id)message withError:(NSError *)error;

/**
 * Indicates that the client had trouble deserializing a message.
 * @param client The BayeuxClient
 * @param message The message that could not be deserialized.
 * @param error The error that occurred.
 */
- (void)bayeuxClient:(BayeuxClient *)client failedToDeserializeMessage:(id)message withError:(NSError *)error;

/**
 * The client encountered an error.
 * @param error Details about the error.
 */
- (void)bayeuxClient:(BayeuxClient *)client failedWithError:(NSError *)error;

/**
 * The client successfully disconnected from the Bayeux server.
 * @param client The BayeuxClient
 */
- (void)bayeuxClientDidDisconnect:(BayeuxClient *)client;

@end


#pragma mark - BayeuxClient

@interface BayeuxClient : NSObject <SRWebSocketDelegate>

/// Used to assign a delegate to the BayeuxClient
@property (weak) id <BayeuxClientDelegate> delegate;

/// URL of the Bayeux server
@property (readonly) NSURL *url;

/// YES if the client is connected to the realtime service
@property (readonly, getter = isConnected) BOOL connected;

/// How often to ping the server (default: 30 seconds)
@property NSTimeInterval pingInterval;


/**
 * Instantiates the BayeuxClient with the given URL.
 * @param url URL of the server in "ws://domain.ext/path" format
 * @return A BayeuxClient instance
 */
- (instancetype)initWithURLString:(NSString *)url;

/**
 * Instantiates the BayeuxClient with the given URL.
 * @param url URL of the server in "ws://domain.ext/path" format
 * @return A BayeuxClient instance
 */
- (instancetype)initWithURL:(NSURL *)url;

/**
 * Attempts to connect to the Bayeux server
 */
- (void)connect;

/**
 * Subscribe to a channel. You'll want to assign a delegate that implements bayeuxClient:receivedMessage:fromChannel: to receive the message.
 * @param channel The channel to subscribe to.
 */
- (void)subscribeToChannel:(NSString *)channel;

/**
 * Unsubscribe from a channel.
 * @param channel The channel to unsubscribe from.
 */
- (void)unsubscribeFromChannel:(NSString *)channel;

/**
 * Publish a message to a channel.
 * @param data The message to publish - NSJSONSerialization must be able to serialize it
 * @param channel Channel to publish to.
 * @return A unique message ID which can be used to identify the success of the message when/if the delegate bayeuxClient:publishedMessageId:toChannel:error: is called. Please keep in mind that the server is not required to reply to publish events.
 */
- (NSString *)publishMessage:(id)data toChannel:(NSString *)channel;

/**
 * Add an extension
 * @param extension An object that implements the extension protocol - a strong reference will be held to this object, so you may want to wrap in an [NSValue valueWithNonretainedObject:] if you want a weak reference instead.
 */
- (void)addExtension:(NSObject <BayeuxClientExtension> *)extension;

/**
 * Removes an extension
 * @param extension An extension object that was previously added to the client.
 */
- (void)removeExtension:(NSObject <BayeuxClientExtension> *)extension;

/**
 * Disconnect from the Bayeux server
 */
- (void)disconnect;

@end
