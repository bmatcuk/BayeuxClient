# BayeuxClient

A client implementation of the Bayeux protocol for OSX and iOS using WebSockets for communication. Using this library, it's easy to connect to a [Faye](http://faye.jcoglan.com/) server, or, theoretically, any other server that implements the [Bayeux Protocol](http://svn.cometd.org/trunk/bayeux/bayeux.html) over a WebSocket.

## Requirements

BayeuxClient supports OSX versions 10.7 and higher, and iOS versions 5.0 and higher. It requires ARC support, in addition to a few other compiler tricks that are only available in Apple's LLVM Compiler v4.0+ (xcode 4.4+), or the open source LLVM Compiler v3.1+.

BayeuxClient uses [SocketRocket](https://github.com/square/SocketRocket) to handle the WebSocket connection.

## Installation

The recommended installation method is via CocoaPods. Add the following to your Podfile:

```ruby
pod 'BayeuxClient', '~> 1.0.0'
```

and then run `pod install`. This will download and install BayeuxClient and the SocketRocket dependency for your project.

## Usage

Import the `BayeuxClient.h` header file into your project and implement the `BayeuxClientDelegate` protocol:

```objc
// BayeuxTest.h
#import <Foundation/Foundation.h>
#import "BayeuxClient.h"

@interface BayeuxTest : NSObject <BayeuxClientDelegate>

@property BayeuxClient *client;

@end


// BayeuxTest.m
#import "BayeuxTest.h"

@implementation BayeuxTest

- (void)connectToServer
{
  // initialize the client with the URL to the server... may also use http or https protocols.
  self.client = [[BayeuxClient alloc] initWithURLString:@"ws://domain.ext/path"];

  // subscribe to a channel - you can call subscribeToChannel: before or after you connect
  [self.client subscribeToChannel:@"/example/channel"];

  // assign myself to be the delegate (see BayeuxClientDelegate methods implemented below)
  self.client.delegate = self;

  // connect
  [self.client connect];
}

#pragma mark - Required BayeuxClientDelegate methods

- (void)bayeuxClient:(BayeuxClient *)client receivedMessage:(NSDictionary *)message fromChannel:(NSString *)channel
{
  NSLog(@"A message was received - this is the only method you MUST implement from the BayeuxClientDelegate protocol.");
}

#pragma mark - Optional BayeuxClientDelegate methods

- (void)bayeuxClientDidConnect:(BayeuxClient *)client
{
  NSLog(@"The client connected.");
}

- (void)bayeuxClient:(BayeuxClient *)client subscribedToChannel:(NSString *)channel
{
  NSLog(@"The client successfully connected to a channel.");
}

- (void)bayeuxClient:(BayeuxClient *)client unsubscribedFromChannel:(NSString *)channel
{
  NSLog(@"The client successfully unsubscribed from a channel.");
}

- (void)bayeuxClient:(BayeuxClient *)client publishedMessageId:(NSString *)messageId toChannel:(NSString *)channel error:(NSError *)error
{
  NSLog(@"The server has responded to a published message.");
}

- (void)bayeuxClient:(BayeuxClient *)client failedToSubscribeToChannel:(NSString *)channel withError:(NSError *)error
{
  NSLog(@"The client encountered an error while subscribing to a channel.");
}

- (void)bayeuxClient:(BayeuxClient *)client failedToSerializeMessage:(id)message withError:(NSError *)error
{
  NSLog(@"The client encountered an error while serializing a message.");
}

- (void)bayeuxClient:(BayeuxClient *)client failedToDeserializeMessage:(id)message withError:(NSError *)error
{
  NSLog(@"The client encountered an error while deserializing a message.");
}

- (void)bayeuxClient:(BayeuxClient *)client failedWithError:(NSError *)error
{
  NSLog(@"The client encountered some error which likely caused it to disconnect.");
}

- (void)bayeuxClientDidDisconnect:(BayeuxClient *)client
{
  NSLog(@"The client successfully disconnected gracefully, because you asked it to.");
}

@end
```

When you are done, you may gracefully disconnect by using the `[self.client disconnect]` method. This method will send a disconnect message to the server, which will then reply and fire the `bayeuxClientDidDisconnect:` method on the delegate.

Or you could do a hard disconnect by releasing the client (ie, `self.client = nil` which will cause ARC to release it). The server will realize you've disconnected after a minute or two. Obviously, a graceful disconnect is preferred.

## Publishing

Once you have a client connected, you may publish messages to different channels using:

```objc
messageId = [self.client publishMessage:@"This is a test." toChannel:@"/test/channel";
```

After the message has been published, the server *may* call `bayeuxClient:publishedMessageId:toChannel:error:`. According to the Bayeux protocol documentation, the server is not required to respond. But, if it does, it will call `bayeuxClient:publishedMessageId:toChannel:error:` on your delegate. The `messageId` argument will match the value returned from `publishMessage:toChannel:` and the `error` argument will either be `nil`, meaning the publish was successful, or an `NSError` describing why the message could not be published.

## Extensions

It is also possible to insert Bayeux Extensions. These extensions can be used to modify a message just before it is sent to the server, or just after they are received from the server and are typically used to implement some custom authentication schemes. An extension class implements the `BayeuxClientExtension` protocol:

```objc
// BayeuxTestExtension.h
#import <Foundation/Foundation.h>
#import "BayeuxClient.h"

@interface BayeuxTestExtension : NSObject <BayeuxClientExtension>
@end


// BayeuxTestExtension.m
#import "BayeuxTestExtension.h"

@implement BayeuxTestExtension

// implement one or both of these optional methods

- (BOOL)bayeuxClient:(BayeuxClient *)client willSendMessage:(NSMutableDictionary *)message
{
  NSLog(@"The client is just about to send a message to the server.");
  return YES;
}

- (BOOL)bayeuxClient:(BayeuxClient *)client willReceiveMessage:(NSMutableDictionary *)message
{
  NSLog(@"The client just received a message from the server.");
  return YES;
}

@end
```

Both methods return a `BOOL`. If you return `NO`, the message will be thrown away (ie, the message won't be sent to the server, or the received message won't be processed). The extension can be added with a:

```objc
[self.client addExtension:[[BayeuxTestExtension alloc] init]];
```

The client maintains a strong reference to the extension.

## Known Issues

1. Message publishing hasn't been tested (I didn't need publishing for my project), but should work.
2. There's no way to substitute a different transport protocol.
