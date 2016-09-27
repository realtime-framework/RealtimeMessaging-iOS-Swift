//
//  OrtcClient.swift
//  OrtcClient
//
//  Created by João Caixinha on 21/1/16.
//  Copyright (c) 2016 Realtime.co. All rights reserved.
//

import Foundation
import Starscream

let heartbeatDefaultTime = 15// Heartbeat default interval time

let heartbeatDefaultFails = 3// Heartbeat default max fails

let heartbeatMaxTime = 60
let heartbeatMinTime = 10
let heartbeatMaxFails = 6
let heartbeatMinFails = 1

/**
 * Delegation protocol for ortc client events
 */
public protocol OrtcClientDelegate{
    ///---------------------------------------------------------------------------------------
    /// @name Instance Methods
    ///--------------------------------------------------------------------------------------
    /**
     * Occurs when the client connects.
     *
     * - parameter ortc: The ORTC object.
     */
    func onConnected(ortc: OrtcClient)
    /**
     * Occurs when the client disconnects.
     *
     * - parameter ortc: The ORTC object.
     */
    
    func onDisconnected(ortc: OrtcClient)
    /**
     * Occurs when the client subscribes to a channel.
     *
     * - parameter ortc: The ORTC object.
     * - parameter channel: The channel name.
     */
    
    func onSubscribed(ortc: OrtcClient, channel: String)
    /**
     * Occurs when the client unsubscribes from a channel.
     *
     * - parameter ortc: The ORTC object.
     * - parameter channel: The channel name.
     */
    
    func onUnsubscribed(ortc: OrtcClient, channel: String)
    /**
     * Occurs when there is an exception.
     *
     * - parameter ortc: The ORTC object.
     * - parameter error: The occurred exception.
     */
    
    func onException(ortc: OrtcClient, error: NSError)
    /**
     * Occurs when the client attempts to reconnect.
     *
     * - parameter ortc: The ORTC object.
     */
    
    func onReconnecting(ortc: OrtcClient)
    /**
     * Occurs when the client reconnects.
     *
     * - parameter ortc: The ORTC object.
     */
    
    func onReconnected(ortc: OrtcClient)
}

/**
 *Part of the The Realtime® Framework, Realtime Cloud Messaging (aka ORTC) is a secure, fast and highly scalable cloud-hosted Pub/Sub real-time message broker for web and mobile apps.
 *
 *If your website or mobile app has data that needs to be updated in the user’s interface as it changes (e.g. real-time stock quotes or ever changing social news feed) Realtime Cloud Messaging is the reliable, easy, unbelievably fast, “works everywhere” solution.
 
 Example:
 
 ```swift
 import RealtimeMessaging_iOS_Swift
 
 class OrtcClass: NSObject, OrtcClientDelegate{
 let APPKEY = "<INSERT_YOUR_APP_KEY>"
 let TOKEN = "guest"
 let METADATA = "swift example"
 let URL = "https://ortc-developers.realtime.co/server/ssl/2.1/"
 var ortc: OrtcClient?
 
 func connect()
 {
 self.ortc = OrtcClient.ortcClientWithConfig(self)
 self.ortc!.connectionMetadata = METADATA
 self.ortc!.clusterUrl = URL
 self.ortc!.connect(APPKEY, authenticationToken: TOKEN)
 }
 
 func onConnected(ortc: OrtcClient){
 NSLog("CONNECTED")
 ortc.subscribe("SOME_CHANNEL", subscribeOnReconnected: true, onMessage: { (ortcClient:OrtcClient!, channel:String!, message:String!) -> Void in
 NSLog("Receive message: %@ on channel: %@", message!, channel!)
 })
 }
 
 func onDisconnected(ortc: OrtcClient){
 // Disconnected
 }
 
 func onSubscribed(ortc: OrtcClient, channel: String){
 // Subscribed to the channel
 
 // Send a message
 ortc.send(channel, "Hello world!!!")
 }
 
 func onUnsubscribed(ortc: OrtcClient, channel: String){
 // Unsubscribed from the channel 'channel'
 }
 
 func onException(ortc: OrtcClient, error: NSError){
 // Exception occurred
 }
 
 func onReconnecting(ortc: OrtcClient){
 // Reconnecting
 }
 
 func onReconnected(ortc: OrtcClient){
 // Reconnected
 }
 }
 */
public class OrtcClient: NSObject, WebSocketDelegate {
    ///---------------------------------------------------------------------------------------
    /// @name Properties
    ///---------------------------------------------------------------------------------------
    
    enum opCodes : Int {
        case opValidate
        case opSubscribe
        case opUnsubscribe
        case opException
    }
    
    enum errCodes : Int {
        case errValidate
        case errSubscribe
        case errSubscribeMaxSize
        case errUnsubscribeMaxSize
        case errSendMaxSize
    }
    
    let OPERATION_PATTERN: String = "^a\\[\"\\{\\\\\"op\\\\\":\\\\\"(.*?[^\"]+)\\\\\",(.*?)\\}\"\\]$"
    let VALIDATED_PATTERN: String = "^(\\\\\"up\\\\\":){1}(.*?)(,\\\\\"set\\\\\":(.*?))?$"
    let CHANNEL_PATTERN: String = "^\\\\\"ch\\\\\":\\\\\"(.*?)\\\\\"$"
    let EXCEPTION_PATTERN: String = "^\\\\\"ex\\\\\":\\{(\\\\\"op\\\\\":\\\\\"(.*?[^\"]+)\\\\\",)?(\\\\\"ch\\\\\":\\\\\"(.*?)\\\\\",)?\\\\\"ex\\\\\":\\\\\"(.*?)\\\\\"\\}$"
    let RECEIVED_PATTERN: String = "^a\\[\"\\{\\\\\"ch\\\\\":\\\\\"(.*?)\\\\\",\\\\\"m\\\\\":\\\\\"([\\s\\S]*?)\\\\\"\\}\"\\]$"
    let RECEIVED_PATTERN_FILTERED: String = "^a\\[\"\\{\\\\\"ch\\\\\":\\\\\"(.*?)\\\\\",\\\\\"f\\\\\":(.*),\\\\\"m\\\\\":\\\\\"([\\s\\S]*?)\\\\\"\\}\"\\]$"
    let MULTI_PART_MESSAGE_PATTERN: String = "^(.[^_]*?)_(.[^-]*?)-(.[^_]*?)_([\\s\\S]*?)$"
    let CLUSTER_RESPONSE_PATTERN: String = "^var SOCKET_SERVER = \\\"(.*?)\\\";$"
    let DEVICE_TOKEN_PATTERN: String = "[0-9A-Fa-f]{64}"
    let MAX_MESSAGE_SIZE: Int = 600
    let MAX_CHANNEL_SIZE: Int = 100
    let MAX_CONNECTION_METADATA_SIZE: Int = 256
    var SESSION_STORAGE_NAME: String = "ortcsession-"
    let PLATFORM: String = "Apns"
    var webSocket: WebSocket?
    var ortcDelegate: OrtcClientDelegate?
    var subscribedChannels: NSMutableDictionary?
    var permissions: NSMutableDictionary?
    var messagesBuffer: NSMutableDictionary?
    var opCases: NSMutableDictionary?
    var errCases: NSMutableDictionary?
    /**Is the acount application key*/
    public var applicationKey: String?
    /**Is the authentication token for this client*/
    public var authenticationToken: String?
    /**Sets if client url is from cluster*/
    public var isCluster: Bool? = true
    
    var isConnecting: Bool?
    var isReconnecting: Bool?
    var hasConnectedFirstTime: Bool?
    var stopReconnecting: Bool?
    var doFallback: Bool?
    var sessionCreatedAt: NSDate?
    var sessionExpirationTime: Int?
    // Time in seconds
    var heartbeatTime: Int?
    // = heartbeatDefaultTime; // Heartbeat interval time
    var heartbeatFails: Int?
    // = heartbeatDefaultFails; // Heartbeat max fails
    var heartbeatTimer: NSTimer?
    public var heartbeatActive: Bool?
    
    var pid: NSString?
    
    /**Client url connection*/
    public var url: NSString?
    /**Client url connection*/
    public var clusterUrl: NSString?
    /**Client connection metadata*/
    public var connectionMetadata: NSString?
    var announcementSubChannel: NSString?
    var sessionId: NSString?
    var connectionTimeout: Int32?
    /**Client connection state*/
    public var isConnected: Bool?
    
    //MARK: Public methods
    
    /**
     * Initializes a new instance of the ORTC class.
     *
     * - parameter delegate: The object holding the ORTC callbacks, usually 'self'.
     *
     * - returns: New instance of the OrtcClient class.
     */
    public static func ortcClientWithConfig(delegate: OrtcClientDelegate) -> OrtcClient{
        return OrtcClient(config: delegate)
    }
    
    init(config delegate: OrtcClientDelegate) {
        
        super.init()
        if opCases == nil {
            opCases = NSMutableDictionary(capacity: 4)
            opCases!["ortc-validated"] = NSNumber(integer: opCodes.opValidate.rawValue)
            opCases!["ortc-subscribed"] = NSNumber(integer: opCodes.opSubscribe.rawValue)
            opCases!["ortc-unsubscribed"] = NSNumber(integer: opCodes.opUnsubscribe.rawValue)
            opCases!["ortc-error"] = NSNumber(integer: opCodes.opException.rawValue)
        }
        if errCases == nil {
            errCases = NSMutableDictionary(capacity: 5)
            errCases!["validate"] = NSNumber(integer: errCodes.errValidate.rawValue)
            errCases!["subscribe"] = NSNumber(integer: errCodes.errSubscribe.rawValue)
            errCases!["subscribe_maxsize"] = NSNumber(integer: errCodes.errSubscribeMaxSize.rawValue)
            errCases!["unsubscribe_maxsize"] = NSNumber(integer: errCodes.errUnsubscribeMaxSize.rawValue)
            errCases!["send_maxsize"] = NSNumber(integer: errCodes.errSendMaxSize.rawValue)
        }
        //apply properties
        self.ortcDelegate = delegate
        connectionTimeout = 5
        // seconds
        sessionExpirationTime = 30
        // minutes
        isConnected = false
        isConnecting = false
        isReconnecting = false
        hasConnectedFirstTime = false
        doFallback = true
        self.permissions = nil
        self.subscribedChannels = NSMutableDictionary()
        self.messagesBuffer = NSMutableDictionary()
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "receivedNotification:", name: "ApnsNotification", object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "receivedNotification:", name: "ApnsRegisterError", object: nil)
        heartbeatTime = heartbeatDefaultTime
        // Heartbeat interval time
        heartbeatFails = heartbeatDefaultFails
        // Heartbeat max fails
        heartbeatTimer = nil
        heartbeatActive = false
    }
    
    /**
     * Connects with the application key and authentication token.
     *
     * - parameter applicationKey: The application key.
     * - parameter authenticationToken: The authentication token.
     */
    public func connect(applicationKey:NSString?, authenticationToken:NSString?){
        if isConnected == true {
            self.delegateExceptionCallback(self, error: self.generateError("Already connected"))
        } else if self.url != nil && self.clusterUrl != nil {
            self.delegateExceptionCallback(self, error: self.generateError("URL and Cluster URL are null or empty"))
        } else if applicationKey == nil {
            self.delegateExceptionCallback(self, error: self.generateError("Application Key is null or empty"))
        } else if authenticationToken == nil {
            self.delegateExceptionCallback(self, error: self.generateError("Authentication Token is null or empty"))
        } else if self.isCluster == false && !self.ortcIsValidUrl(self.url as! String) {
            self.delegateExceptionCallback(self, error: self.generateError("Invalid URL"))
        } else if self.isCluster == true && !self.ortcIsValidUrl(self.clusterUrl as! String) {
            self.delegateExceptionCallback(self, error: self.generateError("Invalid Cluster URL"))
        } else if !self.ortcIsValidInput(applicationKey as! String) {
            self.delegateExceptionCallback(self, error: self.generateError("Application Key has invalid characters"))
        } else if !self.ortcIsValidInput(authenticationToken as! String) {
            self.delegateExceptionCallback(self, error: self.generateError("Authentication Token has invalid characters"))
        } else if self.announcementSubChannel != nil && !self.ortcIsValidInput(self.announcementSubChannel as! String) {
            self.delegateExceptionCallback(self, error: self.generateError("Announcement Subchannel has invalid characters"))
        } else if !self.isEmpty(self.connectionMetadata) && self.connectionMetadata!.length > MAX_CONNECTION_METADATA_SIZE {
            self.delegateExceptionCallback(self, error: self.generateError("Connection metadata size exceeds the limit of \(MAX_CONNECTION_METADATA_SIZE) characters"))
        } else if self.isConnecting == true {
            self.delegateExceptionCallback(self, error: self.generateError("Already trying to connect"))
        } else {
            self.applicationKey = applicationKey as? String
            self.authenticationToken = authenticationToken as? String
            self.isConnecting = true
            self.isReconnecting = false
            self.stopReconnecting = false
            self.doConnect(self)
            
        }
    }
    
    /**
     * Disconnects.
     */
    public func disconnect(){
        // Stop the connecting/reconnecting process
        stopReconnecting = true
        isConnecting = false
        isReconnecting = false
        hasConnectedFirstTime = false
        // Clear subscribed channels
        self.subscribedChannels?.removeAllObjects()
        /*
         * Sanity Checks.
         */
        if isConnected == false {
            self.delegateExceptionCallback(self, error: self.generateError("Not connected"))
        } else {
            self.processDisconnect(true)
        }
    }
    
    /**
     * Sends a message to a channel.
     *
     * - parameter channel: The channel name.
     * - parameter message: The message to send.
     */
    public func send(channel:NSString, var message:NSString){
        if self.isConnected == false {
            self.delegateExceptionCallback(self, error: self.generateError("Not connected"))
        } else if self.isEmpty(channel) {
            self.delegateExceptionCallback(self, error: self.generateError("Channel is null or empty"))
        } else if !self.ortcIsValidInput(channel as String) {
            self.delegateExceptionCallback(self, error: self.generateError("Channel has invalid characters"))
        } else if self.isEmpty(message) {
            self.delegateExceptionCallback(self, error: self.generateError("Message is null or empty"))
        } else {
            message = message.stringByReplacingOccurrencesOfString("\\", withString: "\\\\").stringByReplacingOccurrencesOfString("\n", withString: "\\n")
            message = message.stringByReplacingOccurrencesOfString("\"", withString: "\\\"")
            let channelBytes: NSData = channel.dataUsingEncoding(NSUTF8StringEncoding)!
            if channelBytes.length >= MAX_CHANNEL_SIZE {
                self.delegateExceptionCallback(self, error: self.generateError("Channel size exceeds the limit of \(MAX_CHANNEL_SIZE) characters"))
            } else {
                let domainChannelIndex: Int = channel.rangeOfString(":").location
                var channelToValidate: NSString = channel
                var hashPerm: String?
                if domainChannelIndex != NSNotFound {
                    channelToValidate = (channel as NSString).substringToIndex(domainChannelIndex + 1) + "*"
                }
                if self.permissions != nil {
                    if self.permissions![channelToValidate] != nil {
                        hashPerm = self.permissions!.objectForKey(channelToValidate) as? String
                    } else{
                        hashPerm = self.permissions!.objectForKey(channel) as? String
                    }
                }
                if self.permissions != nil && hashPerm == nil {
                    self.delegateExceptionCallback(self, error: self.generateError("No permission found to send to the channel '\(channel)'"))
                } else {
                    let messageBytes: NSData = NSData(bytes: message.UTF8String, length: message.lengthOfBytesUsingEncoding(NSUTF8StringEncoding))
                    let messageParts: NSMutableArray = NSMutableArray()
                    var pos: Int = 0
                    var remaining: Int
                    let messageId: String = self.generateId(8)
                    
                    
                    while (UInt(messageBytes.length - pos) > 0) {
                        remaining = messageBytes.length - pos
                        let arraySize: Int
                        if remaining >= MAX_MESSAGE_SIZE-channelBytes.length {
                            arraySize = MAX_MESSAGE_SIZE-channelBytes.length
                        } else {
                            arraySize = remaining
                        }
                        
                        let messagePart = Array(UnsafeBufferPointer(start: UnsafePointer<UInt8>(messageBytes.bytes + pos), count: arraySize))
                        let res:NSString? = NSString(bytes: messagePart, length: arraySize, encoding: NSUTF8StringEncoding)
                        if res != nil{
                            messageParts.addObject(res!)
                        }
                        pos += arraySize
                    }
                    var counter: Int32 = 1
                    for messageToSend in messageParts {
                        let encodedData: NSString = NSString(data: NSData(bytes: (messageToSend as! NSString).UTF8String, length: (messageToSend as! NSString).lengthOfBytesUsingEncoding(NSUTF8StringEncoding)), encoding: NSUTF8StringEncoding)! as NSString
                        let aString: NSString = "\"send;\(applicationKey!);\(authenticationToken!);\(channel);\(hashPerm);\(messageId)_\(counter)-\((Int32(messageParts.count)))_\(encodedData)\""
                        self.webSocket?.writeString(aString as String)
                        counter++
                    }
                    
                }
                
            }
            
        }
        
    }
    
    /**
     * Subscribes to a channel to receive messages sent to it.
     *
     * - parameter channel: The channel name.
     * - parameter subscribeOnReconnected: Indicates whether the client should subscribe to the channel when reconnected (if it was previously subscribed when connected).
     * - parameter onMessage: The callback called when a message arrives at the channel.
     */
    public func subscribe(channel:String, subscribeOnReconnected:Bool, onMessage:(ortc:OrtcClient, channel:String, message:String)->Void){
        self.subscribeChannel(channel, withNotifications: WITHOUT_NOTIFICATIONS, subscribeOnReconnect: subscribeOnReconnected, withFilter: false, filter: "", onMessage: onMessage, onMessageWithFilter: nil)
    }
    
    
    /**
     * Subscribes to a channel to receive messages sent to it.
     *
     * - parameter channel: The channel name.
     * - parameter subscribeOnReconnected: Indicates whether the client should subscribe to the channel when reconnected (if it was previously subscribed when connected).
     * - parameter filter: The filter to apply to the channel messages.
     * - parameter onMessageWithFilter: The callback called when a message arrives at the channel.
     */
    public func subscribeWithFilter(channel:String, subscribeOnReconnected:Bool, filter:String ,onMessageWithFilter:(ortc:OrtcClient, channel:String, filtered:Bool, message:String)->Void){
        self.subscribeChannel(channel, withNotifications: WITHOUT_NOTIFICATIONS, subscribeOnReconnect: subscribeOnReconnected, withFilter: true, filter: filter, onMessage: nil, onMessageWithFilter: onMessageWithFilter)
    }
    
    /**
     * Subscribes to a channel, with Push Notifications Service, to receive messages sent to it.
     *
     * - parameter channel: The channel name. Only channels with alphanumeric name and the following characters: "_" "-" ":" are allowed.
     * - parameter subscribeOnReconnected: Indicates whether the client should subscribe to the channel when reconnected (if it was previously subscribed when connected).
     * - parameter onMessage: The callback called when a message or a Push Notification arrives at the channel.
     */
    public func subscribeWithNotifications(channel:String, subscribeOnReconnected:Bool, onMessage:(ortc:OrtcClient, channel:String, message:String)->Void){
        self.subscribeChannel(channel, withNotifications: WITH_NOTIFICATIONS, subscribeOnReconnect: subscribeOnReconnected, withFilter: false, filter: "", onMessage: onMessage, onMessageWithFilter: nil)
    }
    
    /**
     * Unsubscribes from a channel to stop receiving messages sent to it.
     *
     * - parameter channel: The channel name.
     */
    public func unsubscribe(channel:String){
        let channelSubscription:ChannelSubscription? = (self.subscribedChannels!.objectForKey(channel as String) as? ChannelSubscription);
        
        if isConnected == false {
            self.delegateExceptionCallback(self, error: self.generateError("Not connected"))
        } else if self.isEmpty(channel) {
            self.delegateExceptionCallback(self, error: self.generateError("Channel is null or empty"))
        } else if !self.ortcIsValidInput(channel) {
            self.delegateExceptionCallback(self, error: self.generateError("Channel has invalid characters"))
        } else if channelSubscription!.isSubscribed == false {
            self.delegateExceptionCallback(self, error: self.generateError("Not subscribed to the channel \(channel)"))
        } else {
            let channelBytes: NSData = NSData(bytes: (channel as NSString).UTF8String, length: channel.lengthOfBytesUsingEncoding(NSUTF8StringEncoding))
            if channelBytes.length >= MAX_CHANNEL_SIZE {
                self.delegateExceptionCallback(self, error: self.generateError("Channel size exceeds the limit of \(MAX_CHANNEL_SIZE) characters"))
            } else {
                var aString: NSString = NSString()
                if channelSubscription?.withNotifications == true {
                    if !self.isEmpty(OrtcClient.getDEVICE_TOKEN()!) {
                        aString = "\"unsubscribe;\(applicationKey!);\(channel);\(OrtcClient.getDEVICE_TOKEN()!);\(PLATFORM)\""
                    } else {
                        aString = "\"unsubscribe;\(applicationKey!);\(channel)\""
                        
                    }
                } else {
                    aString = "\"unsubscribe;\(applicationKey!);\(channel)\""
                }
                if !self.isEmpty(aString) {
                    self.webSocket?.writeString(aString as String)
                }
            }
        }
    }
    
    func checkChannelSubscription(channel:String, withNotifications:Bool) -> Bool{
        let channelSubscription:ChannelSubscription? = self.subscribedChannels!.objectForKey(channel as NSString) as? ChannelSubscription
        
        if self.isConnected == false{
            self.delegateExceptionCallback(self, error: self.generateError("Not connected"))
            return false
        } else if self.isEmpty(channel) {
            self.delegateExceptionCallback(self, error: self.generateError("Channel is null or empty"))
            return false
        } else if withNotifications {
            if !self.ortcIsValidChannelForMobile(channel) {
                self.delegateExceptionCallback(self, error: self.generateError("Channel has invalid characters"))
                return false
            }
        } else if !self.ortcIsValidInput(channel) {
            self.delegateExceptionCallback(self, error: self.generateError("Channel has invalid characters"))
            return false
        } else if channelSubscription?.isSubscribing == true {
            self.delegateExceptionCallback(self, error: self.generateError("Already subscribing to the channel \(channel)"))
            return false
        } else if channelSubscription?.isSubscribed == true {
            self.delegateExceptionCallback(self, error: self.generateError("Already subscribed to the channel \(channel)"))
            return false
        } else {
            let channelBytes: NSData = NSData(bytes: (channel as NSString).UTF8String, length: channel.lengthOfBytesUsingEncoding(NSUTF8StringEncoding))
            if channelBytes.length >= MAX_CHANNEL_SIZE {
                self.delegateExceptionCallback(self, error: self.generateError("Channel size exceeds the limit of \(MAX_CHANNEL_SIZE) characters"))
                return false
            }
        }
        return true
    }
    
    func checkChannelPermissions(channel:NSString)->NSString?{
        let domainChannelIndex: Int = Int(channel.rangeOfString(":").location)
        var channelToValidate: NSString = channel
        var hashPerm: NSString?
        if domainChannelIndex != NSNotFound {
            channelToValidate = channel.substringToIndex(domainChannelIndex+1) + "*"
        }
        if self.permissions != nil {
            hashPerm = (self.permissions![channelToValidate] != nil ? self.permissions![channelToValidate] : self.permissions![channel]) as? NSString
            return hashPerm
        }
        if self.permissions != nil && hashPerm == nil {
            self.delegateExceptionCallback(self, error: self.generateError("No permission found to subscribe to the channel '\(channel)'"))
            return nil
        }
        return hashPerm
    }
    
    /**
     * Indicates whether is subscribed to a channel or not.
     *
     * - parameter channel: The channel name.
     *
     * - returns: TRUE if subscribed to the channel or FALSE if not.
     */
    public func isSubscribed(channel:String) -> NSNumber?{
        var result: NSNumber?
        /*
         * Sanity Checks.
         */
        if isConnected == false {
            self.delegateExceptionCallback(self, error: self.generateError("Not connected"))
        } else if self.isEmpty(channel) {
            self.delegateExceptionCallback(self, error: self.generateError("Channel is null or empty"))
        } else if !self.ortcIsValidInput(channel) {
            self.delegateExceptionCallback(self, error: self.generateError("Channel has invalid characters"))
        } else {
            result = NSNumber(bool: false)
            let channelSubscription:ChannelSubscription? = self.subscribedChannels!.objectForKey(channel) as? ChannelSubscription
            if channelSubscription!.isSubscribed == true {
                result = NSNumber(bool: true)
            }else{
                result = NSNumber(bool: false)
            }
        }
        return result
    }
    
    /** Saves the channels and its permissions for the authentication token in the ORTC server.
     @warning This function will send your private key over the internet. Make sure to use secure connection.
     - parameter url: ORTC server URL.
     - parameter isCluster: Indicates whether the ORTC server is in a cluster.
     - parameter authenticationToken: The authentication token generated by an application server (for instance: a unique session ID).
     - parameter authenticationTokenIsPrivate: Indicates whether the authentication token is private (1) or not (0).
     - parameter applicationKey: The application key provided together with the ORTC service purchasing.
     - parameter timeToLive: The authentication token time to live (TTL), in other words, the allowed activity time (in seconds).
     - parameter privateKey: The private key provided together with the ORTC service purchasing.
     - parameter permissions: The channels and their permissions (w: write, r: read, p: presence, case sensitive).
     - return: TRUE if the authentication was successful or FALSE if it was not.
     */
    public func saveAuthentication(aUrl:String,
                                   isCluster:Bool,
                                   authenticationToken:String,
                                   authenticationTokenIsPrivate:Bool,
                                   applicationKey:String,
                                   timeToLive:Int,
                                   privateKey:String,
                                   permissions:NSMutableDictionary?)->Bool{
        /*
         * Sanity Checks.
         */
        if self.isEmpty(aUrl) {
            NSException(name: "Url", reason: "URL is null or empty", userInfo: nil).raise()
        } else if self.isEmpty(authenticationToken) {
            NSException(name: "Authentication Token", reason: "Authentication Token is null or empty", userInfo: nil).raise()
        } else if self.isEmpty(applicationKey) {
            NSException(name: "Application Key", reason: "Application Key is null or empty", userInfo: nil).raise()
        } else if self.isEmpty(privateKey) {
            NSException(name: "Private Key", reason: "Private Key is null or empty", userInfo: nil).raise()
        } else {
            var ret: Bool = false
            var connectionUrl: String? = aUrl
            if isCluster {
                connectionUrl = String(self.getClusterServer(true, aPostUrl: aUrl)!)
            }
            if connectionUrl != nil {
                connectionUrl = connectionUrl!.hasSuffix("/") ? connectionUrl! : connectionUrl! + "/"
                var post: String = "AT=\(authenticationToken)&PVT=\(authenticationTokenIsPrivate ? "1" : "0")&AK=\(applicationKey)&TTL=\(timeToLive)&PK=\(privateKey)"
                if permissions != nil && permissions!.count > 0 {
                    post = post + "&TP=\(CUnsignedLong(permissions!.count))"
                    let keys: [AnyObject]? = permissions!.allKeys
                    // the dictionary keys
                    for key in keys! {
                        post = post + "&\(key)=\(permissions![key as! String] as! String)"
                    }
                }
                let postData: NSData? = post.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true)
                let postLength: String? = "\(CUnsignedLong((postData! as NSData).length))"
                let request: NSMutableURLRequest = NSMutableURLRequest()
                request.URL = NSURL(string: connectionUrl! + "authenticate")
                request.HTTPMethod = "POST"
                request.setValue(postLength, forHTTPHeaderField: "Content-Length")
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.HTTPBody = postData
                // Send request and get response
                
                
                let semaphore = dispatch_semaphore_create(0)
                
                NSURLSession.sharedSession().dataTaskWithRequest(request, completionHandler: { (data:NSData?, urlResponse:NSURLResponse?, error:NSError?) -> Void in
                    if urlResponse != nil {
                        ret = Bool((urlResponse as! NSHTTPURLResponse).statusCode == 201)
                    }else if error != nil{
                        ret = false
                    }
                    dispatch_semaphore_signal(semaphore)
                }).resume()
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
            } else {
                NSException(name: "Get Cluster URL", reason: "Unable to get URL from cluster", userInfo: nil).raise()
            }
            return ret
        }
        return false
    }
    
    /** Enables presence for the specified channel with first 100 unique metadata if true.
     
     @warning This function will send your private key over the internet. Make sure to use secure connection.
     - parameter url: Server containing the presence service.
     - parameter isCluster: Specifies if url is cluster.
     - parameter applicationKey: Application key with access to presence service.
     - parameter privateKey: The private key provided when the ORTC service is purchased.
     - parameter channel: Channel with presence data active.
     - parameter metadata: Defines if to collect first 100 unique metadata.
     - parameter callback: Callback with error (NSError) and result (NSString) parameters
     */
    public func enablePresence(aUrl:String, isCluster:Bool,
                               applicationKey:String,
                               privateKey:String,
                               channel:String,
                               metadata:Bool,
                               callback:(error:NSError?, result:NSString?)->Void){
        self.setPresence(true, aUrl: aUrl, isCluster: isCluster, applicationKey: applicationKey, privateKey: privateKey, channel: channel, metadata: metadata, callback: callback)
    }
    
    /** Disables presence for the specified channel.
     
     @warning This function will send your private key over the internet. Make sure to use secure connection.
     - parameter url: Server containing the presence service.
     - parameter isCluster: Specifies if url is cluster.
     - parameter applicationKey: Application key with access to presence service.
     - parameter privateKey: The private key provided when the ORTC service is purchased.
     - parameter channel: Channel with presence data active.
     - parameter callback: Callback with error (NSError) and result (NSString) parameters
     */
    public func disablePresence(aUrl:String,
                                isCluster:Bool,
                                applicationKey:String,
                                privateKey:String,
                                channel:String,
                                callback:(error:NSError?, result:NSString?)->Void){
        self.setPresence(false, aUrl: aUrl, isCluster: isCluster, applicationKey: applicationKey, privateKey: privateKey, channel: channel, metadata: false, callback: callback)
    }
    
    func setPresence(enable:Bool, aUrl:String, isCluster:Bool,
                     applicationKey:String,
                     privateKey:String,
                     channel:String,
                     metadata:Bool,
                     callback:(error:NSError?, result:NSString?)->Void){
        if self.isEmpty(aUrl) {
            NSException(name: "Url", reason: "URL is null or empty", userInfo: nil).raise()
        } else if self.isEmpty(applicationKey) {
            NSException(name: "Application Key", reason: "Application Key is null or empty", userInfo: nil).raise()
        } else if self.isEmpty(privateKey) {
            NSException(name: "Private Key", reason: "Private Key is null or empty", userInfo: nil).raise()
        } else if self.isEmpty(channel) {
            NSException(name: "Channel", reason: "Channel is null or empty", userInfo: nil).raise()
        } else if !self.ortcIsValidInput(channel) {
            NSException(name: "Channel", reason: "Channel has invalid characters", userInfo: nil).raise()
        } else {
            var connectionUrl: String? = aUrl
            if isCluster {
                connectionUrl = String(self.getClusterServer(true, aPostUrl: aUrl))
            }
            if connectionUrl != nil {
                connectionUrl = connectionUrl!.hasSuffix("/") ? connectionUrl! : connectionUrl! + "/"
                var path: String = ""
                var content: String = ""
                
                if enable {
                    path = "presence/enable/\(applicationKey)/\(channel)"
                    content = "privatekey=\(privateKey)&metadata=\((metadata ? "1" : "0"))"
                }else{
                    path = "presence/disable/\(applicationKey)/\(channel)"
                    content = "privatekey=\(privateKey)"
                }
                
                connectionUrl = connectionUrl! + path
                let postData: NSData = (content as NSString).dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true)!
                let postLength: String = "\(CUnsignedLong((postData as NSData).length))"
                let request: NSMutableURLRequest = NSMutableURLRequest()
                request.URL = NSURL(string: connectionUrl!)
                request.HTTPMethod = "POST"
                request.setValue(postLength, forHTTPHeaderField: "Content-Length")
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.HTTPBody = postData
                let pr:PresenceRequest = PresenceRequest()
                pr.callback = callback
                pr.post(request)
            } else {
                let error: NSError = self.generateError("Unable to get URL from cluster")
                callback(error: error, result: nil)
            }
        }
    }
    
    
    /**
     * Gets a NSDictionary indicating the subscriptions in the specified channel and if active the first 100 unique metadata.
     *
     * - parameter url: Server containing the presence service.
     * - parameter isCluster: Specifies if url is cluster.
     * - parameter applicationKey: Application key with access to presence service.
     * - parameter authenticationToken: Authentication token with access to presence service.
     * - parameter channel: Channel with presence data active.
     * - parameter callback: Callback with error (NSError) and result (NSDictionary) parameters
     */
    public func presence(aUrl:String,
                         isCluster:Bool,
                         applicationKey:String,
                         authenticationToken:String,
                         channel:String,
                         callback:(error:NSError?, result:NSDictionary?)->Void){
        /*
         * Sanity Checks.
         */
        if self.isEmpty(aUrl) {
            NSException(name: "Url", reason: "URL is null or empty", userInfo: nil).raise()
        } else if self.isEmpty(applicationKey) {
            NSException(name: "Application Key", reason: "Application Key is null or empty", userInfo: nil).raise()
        } else if self.isEmpty(authenticationToken) {
            NSException(name: "Authentication Token", reason: "Authentication Token is null or empty", userInfo: nil).raise()
        } else if self.isEmpty(channel) {
            NSException(name: "Channel", reason: "Channel is null or empty", userInfo: nil).raise()
        } else if !self.ortcIsValidInput(channel) {
            NSException(name: "Channel", reason: "Channel has invalid characters", userInfo: nil).raise()
        } else {
            var connectionUrl: String? = aUrl
            if isCluster {
                connectionUrl = String(self.getClusterServer(true, aPostUrl: aUrl))
            }
            if connectionUrl != nil {
                connectionUrl = connectionUrl!.hasSuffix("/") ? connectionUrl! : connectionUrl! + "/"
                let path: String = "presence/\(applicationKey)/\(authenticationToken)/\(channel)"
                connectionUrl = connectionUrl! + path
                let request: NSMutableURLRequest = NSMutableURLRequest()
                request.URL = NSURL(string: connectionUrl!)
                request.HTTPMethod = "GET"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                let pr:PresenceRequest = PresenceRequest()
                pr.callbackDictionary = callback
                pr.get(request)
            } else {
                let error: NSError = self.generateError("Unable to get URL from cluster")
                callback(error: error, result: nil)
            }
        }
    }
    
    /**
     * Get heartbeat interval.
     */
    public func getHeartbeatTime()->Int?{
        return self.heartbeatTime
    }
    /**
     * Set heartbeat interval.
     */
    public func setHeartbeatTime(time:Int){
        self.heartbeatTime = time
    }
    /**
     * Get how many times can the client fail the heartbeat.
     */
    public func getHeartbeatFails()->Int?{
        return self.heartbeatFails
    }
    /**
     * Set heartbeat fails. Defines how many times can the client fail the heartbeat.
     */
    public func setHeartbeatFails(time:Int){
        self.heartbeatFails = time
    }
    /**
     * Indicates whether heartbeat is active or not.
     */
    public func isHeartbeatActive()->Bool{
        return self.isHeartbeatActive()
    }
    /**
     * Enables the client heartbeat
     */
    public func enableHeartbeat(){
        self.heartbeatActive = true
    }
    /**
     * Disables the client heartbeat
     */
    public func disableHeartbeat(){
        self.heartbeatActive = false
    }
    
    func startHeartbeatLoop(){
        if heartbeatTimer == nil && heartbeatActive == true {
            dispatch_async(dispatch_get_main_queue(),{
                self.heartbeatTimer = NSTimer.scheduledTimerWithTimeInterval(Double(self.heartbeatTime!), target: self, selector: "heartbeatLoop", userInfo: nil, repeats: true)
            })
        }
    }
    
    func stopHeartbeatLoop(){
        if heartbeatTimer != nil {
            heartbeatTimer!.invalidate()
        }
        heartbeatTimer = nil
    }
    
    func heartbeatLoop(){
        if heartbeatActive == true {
            self.webSocket!.writeString("\"b\"")
        } else {
            self.stopHeartbeatLoop()
            
        }
    }
    
    static var ortcDEVICE_TOKEN: String?
    public class func setDEVICE_TOKEN(deviceToken: String) {
        ortcDEVICE_TOKEN = deviceToken;
    }
    
    public class func getDEVICE_TOKEN() -> String? {
        return ortcDEVICE_TOKEN
    }
    
    
    func receivedNotification(notification: NSNotification) {
        // [notification name] should be @"ApnsNotification" for received Apns Notififications
        if (notification.name == "ApnsNotification") {
            let userInfo:NSDictionary = notification.userInfo! as NSDictionary
            let ortcMessage: String = "a[\"{\\\"ch\\\":\\\"\(userInfo["C"] as! String)\\\",\\\"m\\\":\\\"\(userInfo["M"] as! String)\\\"}\"]"
            self.parseReceivedMessage(ortcMessage)
        }
        // [notification name] should be @"ApnsRegisterError" if an error ocured on RegisterForRemoteNotifications
        if (notification.name == "ApnsRegisterError") {
            self.delegateExceptionCallback(self, error: (NSError(domain: "ApnsRegisterError", code: 0, userInfo: notification.userInfo)))
        }
    }
    
    func subscribeChannel(channel:String,
                          withNotifications:Bool,
                          subscribeOnReconnect:Bool,
                          withFilter:Bool,
                          filter:String,
                          onMessage:((ortc:OrtcClient, channel:String, message:String)->Void)?,
                          onMessageWithFilter:((ortc:OrtcClient, channel:String, filtered:Bool, message:String)->Void)?){
        
        if Bool(self.checkChannelSubscription(channel, withNotifications: withNotifications)) == true {
            
            let hashPerm: String? = self.checkChannelPermissions(channel) as? String
            
            if self.permissions == nil || (self.permissions != nil && hashPerm != nil) {
                if self.subscribedChannels![channel] == nil {
                    let channelSubscription:ChannelSubscription  = ChannelSubscription();
                    // Set channelSubscription properties
                    channelSubscription.isSubscribing = true
                    channelSubscription.isSubscribed = false
                    channelSubscription.withFilter = withFilter
                    channelSubscription.filter = filter
                    channelSubscription.subscribeOnReconnected = subscribeOnReconnect
                    channelSubscription.onMessage = onMessage
                    channelSubscription.onMessageWithFilter = onMessageWithFilter
                    channelSubscription.withNotifications = withNotifications
                    // Add to subscribed channels dictionary
                    self.subscribedChannels![channel] = channelSubscription
                }
                var aString: String
                if withNotifications {
                    if !self.isEmpty(OrtcClient.getDEVICE_TOKEN()!) {
                        aString = "\"subscribe;\(applicationKey!);\(authenticationToken!);\(channel);\(hashPerm);\(OrtcClient.getDEVICE_TOKEN()!);\(PLATFORM)\""
                    } else {
                        self.delegateExceptionCallback(self, error: self.generateError("Failed to register Device Token. Channel subscribed without Push Notifications"))
                        aString = "\"subscribe;\(applicationKey!);\(authenticationToken!);\(channel);\(hashPerm)\""
                    }
                } else if(withFilter){
                    aString = "\"subscribefilter;\(applicationKey!);\(authenticationToken!);\(channel);\(hashPerm);\(filter)\""
                } else {
                    aString = "\"subscribe;\(applicationKey!);\(authenticationToken!);\(channel);\(hashPerm)\""
                }
                if !self.isEmpty(aString) {
                    self.webSocket?.writeString(aString as String)
                }
            }
        }
    }
    
    func ortcIsValidInput(input: String) -> Bool {
        var opMatch: NSTextCheckingResult?
        do{
            let opRegex: NSRegularExpression = try NSRegularExpression(pattern: "^[\\w-:/.]*$", options: NSRegularExpressionOptions.CaseInsensitive)
            opMatch = opRegex.firstMatchInString(input, options: NSMatchingOptions.ReportProgress, range: NSMakeRange(0, (input as NSString).length))
        }catch{
            return false
        }
        return opMatch != nil ? true : false
    }
    
    func ortcIsValidUrl(input: String) -> Bool {
        var opMatch: NSTextCheckingResult?
        do{
            let opRegex: NSRegularExpression = try NSRegularExpression(pattern: "^\\s*(http|https)://(\\w+:{0,1}\\w*@)?(\\S+)(:[0-9]+)?(/|/([\\w#!:.?+=&%@!\\-/]))?\\s*$", options: NSRegularExpressionOptions.CaseInsensitive)
            opMatch = opRegex.firstMatchInString(input, options: NSMatchingOptions.ReportProgress, range: NSMakeRange(0, (input as NSString).length))
        }catch{
            
        }
        return opMatch != nil ? true : false
    }
    
    func ortcIsValidChannelForMobile(input:String) -> Bool{
        var opMatch: NSTextCheckingResult?
        do{
            let opRegex: NSRegularExpression = try NSRegularExpression(pattern: "^[\\w-:/.]*$", options: NSRegularExpressionOptions.CaseInsensitive)
            opMatch = opRegex.firstMatchInString(input, options: NSMatchingOptions.ReportProgress, range: NSMakeRange(0, (input as NSString).length))
        }catch{
            return false
        }
        return opMatch != nil ? true : false
    }
    
    func isEmpty(thing: AnyObject?) -> Bool {
        return thing == nil ||
            (thing!.respondsToSelector("length") && (thing! as? NSData)?.length == 0) ||
            (thing!.respondsToSelector("count") && (thing! as? [NSArray])?.count == 0)
    }
    
    func generateError(errText: String) -> NSError {
        let errorDetail: NSMutableDictionary = NSMutableDictionary()
        errorDetail.setValue(errText, forKey: NSLocalizedDescriptionKey)
        return NSError(domain: "OrtcClient", code: 1, userInfo: errorDetail as [NSObject : AnyObject])
    }
    
    func doConnect(sender: AnyObject) {
        if heartbeatTimer != nil {
            self.stopHeartbeatLoop()
        }
        if isReconnecting == true {
            self.delegateReconnectingCallback(self)
        }
        if stopReconnecting == false {
            self.processConnect(self)
        }
    }
    
    func parseReceivedMessage(aMessage: NSString?) {
        if aMessage != nil {
            if (!aMessage!.isEqualToString("o") && !aMessage!.isEqualToString("h")){
                var opMatch: NSTextCheckingResult?
                do{
                    let opRegex: NSRegularExpression = try NSRegularExpression(pattern: OPERATION_PATTERN, options: NSRegularExpressionOptions.CaseInsensitive)
                    opMatch = opRegex.firstMatchInString(aMessage! as String, options: NSMatchingOptions.ReportProgress, range: NSMakeRange(0, (aMessage! as NSString).length))
                }catch{
                    return
                }
                
                if opMatch != nil {
                    var operation: String?
                    var arguments: String?
                    let strRangeOp: NSRange? = opMatch!.rangeAtIndex(1)
                    let strRangeArgs: NSRange? = opMatch!.rangeAtIndex(2)
                    if strRangeOp != nil {
                        operation = aMessage!.substringWithRange(strRangeOp!)
                    }
                    if strRangeArgs != nil {
                        arguments = aMessage!.substringWithRange(strRangeArgs!)
                    }
                    if operation != nil {
                        if (opCases![operation!] != nil) {
                            switch opCases![operation!]?.integerValue {
                            case opCodes.opValidate.rawValue?:
                                if arguments != nil {
                                    self.opValidated(arguments!)
                                }
                                break
                            case opCodes.opSubscribe.rawValue?:
                                if arguments != nil {
                                    self.opSubscribed(arguments!)
                                }
                                break
                            case opCodes.opUnsubscribe.rawValue?:
                                if arguments != nil {
                                    self.opUnsubscribed(arguments!)
                                }
                                break
                            case opCodes.opException.rawValue?:
                                if arguments != nil {
                                    self.opException(arguments!)
                                }
                                break
                            default:
                                self.delegateExceptionCallback(self, error: self.generateError("Unknown message received: \(aMessage!)"))
                                break
                            }
                        }
                    } else {
                        self.delegateExceptionCallback(self, error: self.generateError("Unknown message received: \(aMessage!)"))
                    }
                } else {
                    self.opReceive(aMessage! as String)
                }
            }
        }
    }
    
    var balancer:Balancer?
    func processConnect(sender: AnyObject) {
        if stopReconnecting == false {
            balancer = (Balancer(cluster: self.clusterUrl as? String, serverUrl: self.url as? String, isCluster: self.isCluster!, appKey: self.applicationKey!,
                callback:
                { (aBalancerResponse: String?) in
                    
                    if self.isCluster != nil {
                        if self.isEmpty(aBalancerResponse) {
                            self.delegateExceptionCallback(self, error: self.generateError("Unable to get URL from cluster (\(self.clusterUrl!))"))
                            self.url = nil
                        }else{
                            self.url = String(aBalancerResponse!)
                        }
                    }
                    if self.url != nil {
                        var wsScheme: String = "ws"
                        let connectionUrl: NSURL = NSURL(string: self.url! as String)!
                        if connectionUrl.scheme == "https" {
                            wsScheme = "wss"
                        }
                        let serverId: NSString = NSString(format: "%0.3u", self.randomInRangeLo(1, toHi: 1000))
                        let connId: String = self.randomString(8)
                        var connUrl: String = connectionUrl.host!
                        if self.isEmpty(connectionUrl.port) == false {
                            connUrl = connUrl + ":" + connectionUrl.port!.stringValue
                        }
                        let wsUrl: String = "\(wsScheme)://\(connUrl)/broadcast/\(serverId)/\(connId)/websocket"
                        let wurl:NSURL = NSURL(string: wsUrl)!
                        
                        if self.webSocket != nil {
                            self.webSocket!.delegate = nil
                            self.webSocket = nil
                        }
                        
                        self.webSocket = WebSocket(url: wurl)
                        self.webSocket!.delegate = self
                        self.webSocket!.connect()
                        
                    } else {
                        dispatch_async(dispatch_get_main_queue(),{
                            self.timer = NSTimer.scheduledTimerWithTimeInterval(Double(self.connectionTimeout!), target: self, selector: "processConnect:", userInfo: nil, repeats: false)
                        })
                    }
                    
            }))
        }
        
    }
    
    var timer:NSTimer?
    func randomString(size: UInt32) -> String {
        var ret: NSString = ""
        for _ in 0...size {
            let letter: NSString = NSString(format: "%0.1u", self.randomInRangeLo(65, toHi: 90))
            ret = "\(ret)\(CChar(letter.intValue))"
        }
        return ret as String
        
    }
    
    func randomInRangeLo(loBound: UInt32, toHi hiBound: UInt32) -> UInt32 {
        var random: UInt32
        let range: UInt32 = UInt32(hiBound) - UInt32(loBound+1)
        let limit:UInt32 = UINT32_MAX - (UINT32_MAX % range)
        repeat {
            random = arc4random()
        } while random > limit
        return loBound+(random%range)
    }
    
    func processDisconnect(callDisconnectCallback:Bool){
        self.stopHeartbeatLoop()
        self.webSocket!.delegate = nil
        self.webSocket!.disconnect()
        if callDisconnectCallback == true {
            self.delegateDisconnectedCallback(self)
        }
        isConnected = false
        isConnecting = false
        // Clear user permissions
        self.permissions = nil
    }
    
    func createLocalStorage(sessionStorageName: String) {
        sessionCreatedAt = NSDate()
        var plistData: NSData?
        var plistPath: NSString?
        
        do{
            let keys: [AnyObject] = NSArray(objects: "sessionId","sessionCreatedAt") as [AnyObject]
            let objects: [AnyObject] = NSArray(objects: sessionId!,sessionCreatedAt!) as [AnyObject]
            let sessionInfo: [NSObject : AnyObject] = NSDictionary(objects: objects, forKeys: keys as! [NSCopying]) as [NSObject : AnyObject]
            let rootPath: NSString = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory, NSSearchPathDomainMask.UserDomainMask, true)[0]
            plistPath = rootPath.stringByAppendingPathComponent("OrtcClient.plist")
            try plistData = NSPropertyListSerialization.dataWithPropertyList(sessionInfo, format: NSPropertyListFormat.XMLFormat_v1_0, options: NSPropertyListWriteOptions.allZeros)
        }catch{
            
        }
        
        if plistData != nil {
            plistData!.writeToFile(plistPath! as String, atomically: true)
        } else {
            self.delegateExceptionCallback(self, error: self.generateError("Error : Creating local storage"))
            
        }
    }
    
    func readLocalStorage(sessionStorageName: String) -> String? {
        let format:UnsafeMutablePointer<NSPropertyListFormat> = UnsafeMutablePointer<NSPropertyListFormat>()
        var plistPath: String?
        var plistProps: NSDictionary?
        
        let rootPath: NSString = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory, NSSearchPathDomainMask.UserDomainMask, true)[0]
        plistPath = rootPath.stringByAppendingPathComponent("OrtcClient.plist")
        if NSFileManager.defaultManager().fileExistsAtPath(plistPath!) {
            plistPath = NSBundle.mainBundle().pathForResource("OrtcClient", ofType: "plist")
            //NSLog(@"plistPath: %@", plistPath);
            do{
                let plistXML: NSData? = NSFileManager.defaultManager().contentsAtPath(plistPath!)
                if plistXML != nil{
                    plistProps = try (NSPropertyListSerialization.propertyListWithData(plistXML!, options: NSPropertyListMutabilityOptions.MutableContainersAndLeaves, format: format) as? NSDictionary)
                }
            }catch{
                
            }
        }
        if plistProps != nil {
            
            if plistProps!.objectForKey("sessionCreatedAt") != nil {
                sessionCreatedAt = (plistProps!.objectForKey("sessionCreatedAt")!) as? NSDate
            }
            let currentDateTime: NSDate = NSDate()
            let time: NSTimeInterval = currentDateTime.timeIntervalSinceDate(sessionCreatedAt!)
            let minutes: Int = Int(time / 60.0)
            if minutes >= sessionExpirationTime {
                plistProps = nil
            } else if plistProps!.objectForKey("sessionId") != nil {
                sessionId = plistProps!.objectForKey("sessionId") as? NSString
            }
        }
        return sessionId as? String
    }
    
    func getClusterServer(isPostingAuth: Bool, aPostUrl postUrl: String) -> String? {
        var result:String?
        let semaphore = dispatch_semaphore_create(0)
        self.send(isPostingAuth, aPostUrl: postUrl, res: { (res:String) -> () in
            result = res
            dispatch_semaphore_signal(semaphore)
        })
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
        return result
    }
    
    func send(isPostingAuth: Bool, aPostUrl postUrl: String, res:(String)->()){
        // Send request and get response
        var parsedUrl: String = postUrl
        if applicationKey != nil {
            parsedUrl = parsedUrl + "?appkey="
            parsedUrl = parsedUrl + self.applicationKey!
        }
        let request: NSURLRequest = NSURLRequest(URL:NSURL(string: parsedUrl)!)
        
        NSURLSession.sharedSession().dataTaskWithRequest(request, completionHandler: { (data:NSData?, UrlResponse:NSURLResponse?, error:NSError?) -> Void in
            if data != nil
            {
                var result: String = ""
                var resRegex: NSRegularExpression?
                let myString: NSString = NSString(data: data!, encoding: NSUTF8StringEncoding) as NSString!
                do{
                    resRegex = try NSRegularExpression(pattern: self.CLUSTER_RESPONSE_PATTERN, options: NSRegularExpressionOptions.CaseInsensitive)
                }catch{
                    
                }
                let resMatch: NSTextCheckingResult? = resRegex?.firstMatchInString(myString as String, options: NSMatchingOptions.ReportProgress, range: NSMakeRange(0, myString.length))
                if resMatch != nil {
                    let strRange: NSRange? = resMatch!.rangeAtIndex(1)
                    if strRange != nil {
                        result = myString.substringWithRange(strRange!)
                    }
                }
                if !isPostingAuth {
                    if self.isEmpty(result) == true {
                        self.delegateExceptionCallback(self, error: self.generateError("Unable to get URL from cluster (\(parsedUrl))"))
                    }
                }
                res(result)
            }
        }).resume()
    }
    
    func opValidated(message: NSString) {
        var isValid: Bool = false
        var valRegex: NSRegularExpression?
        
        do{
            valRegex = try NSRegularExpression(pattern: VALIDATED_PATTERN, options: NSRegularExpressionOptions.CaseInsensitive)
        }catch{
            
        }
        
        let valMatch: NSTextCheckingResult? = valRegex?.firstMatchInString(message as String, options: NSMatchingOptions.ReportProgress, range: NSMakeRange(0, (message as NSString).length))
        if valMatch != nil{
            isValid = true
            var userPermissions: NSString?
            let strRangePerm: NSRange? = valMatch!.rangeAtIndex(2)
            let strRangeExpi: NSRange? = valMatch!.rangeAtIndex(4)
            
            if strRangePerm!.location != NSNotFound {
                userPermissions = message.substringWithRange(strRangePerm!)
            }
            if strRangeExpi!.location != NSNotFound{
                sessionExpirationTime = (message.substringWithRange(strRangeExpi!)as NSString).integerValue
            }
            if self.isEmpty(self.readLocalStorage(SESSION_STORAGE_NAME + applicationKey!)) {
                self.createLocalStorage(SESSION_STORAGE_NAME + applicationKey!)
            }
            // NOTE: userPermissions = null -> No authentication required for the application key
            if userPermissions != nil && !(userPermissions!.isEqualToString("null")) {
                userPermissions = userPermissions!.stringByReplacingOccurrencesOfString("\\\"", withString: "\"")
                // Parse the string into JSON
                var dictionary: NSDictionary
                do{
                    dictionary = try NSJSONSerialization.JSONObjectWithData(userPermissions!.dataUsingEncoding(NSUTF8StringEncoding)!, options:NSJSONReadingOptions.MutableContainers) as! NSDictionary
                }catch{
                    self.delegateExceptionCallback(self, error: self.generateError("Error parsing the permissions received from server"))
                    return
                }
                
                self.permissions = NSMutableDictionary()
                for key in dictionary.allKeys {
                    // Add to permissions dictionary
                    self.permissions!.setValue(dictionary.objectForKey(key), forKey: key as! String)
                }
            }
        }
        if isValid == true {
            isConnecting = false
            isReconnecting = false
            isConnected = true
            if (hasConnectedFirstTime == true) {
                let channelsToRemove: NSMutableArray = NSMutableArray()
                // Subscribe to the previously subscribed channels
                for channel in self.subscribedChannels! {
                    let channelSubscription:ChannelSubscription = self.subscribedChannels!.objectForKey(channel.key as! String) as! ChannelSubscription!
                    // Subscribe again
                    if channelSubscription.subscribeOnReconnected == true && (channelSubscription.isSubscribing == true || channelSubscription.isSubscribed == true) {
                        channelSubscription.isSubscribing = true
                        channelSubscription.isSubscribed = false
                        let domainChannelIndex: Int = (channel.key as! NSString).rangeOfString(":").location
                        var channelToValidate: String = channel.key
                            as! String
                        var hashPerm: String = ""
                        if domainChannelIndex != NSNotFound {
                            channelToValidate = channel.key.substringToIndex(domainChannelIndex+1) + "*"
                        }
                        if self.permissions != nil {
                            hashPerm = (self.permissions![channelToValidate] != nil ? self.permissions![channelToValidate] : self.permissions![channel.key as! String]) as! String
                        }
                        var aString: NSString = NSString()
                        if channelSubscription.withNotifications == true {
                            if !self.isEmpty(OrtcClient.getDEVICE_TOKEN()!) {
                                aString = "\"subscribe;\(applicationKey!);\(authenticationToken!);\(channel.key);\(hashPerm);\(OrtcClient.getDEVICE_TOKEN()!);\(PLATFORM)\""
                            } else {
                                self.delegateExceptionCallback(self, error: self.generateError("Failed to register Device Token. Channel subscribed without Push Notifications"))
                                aString = "\"subscribe;\(applicationKey!);\(authenticationToken!);\(channel.key);\(hashPerm)\""
                                
                            }
                            
                        } else if (channelSubscription.withFilter == true){
                            aString = "\"subscribefilter;\(applicationKey!);\(authenticationToken!);\(channel.key);\(hashPerm);\(channelSubscription.filter!)\""
                        }
                        else {
                            aString = "\"subscribe;\(applicationKey!);\(authenticationToken!);\(channel.key);\(hashPerm)\""
                            
                        }
                        //NSLog(@"SUB ON ORTC:\n%@",aString);
                        if !self.isEmpty(aString) {
                            self.webSocket?.writeString(aString as String)
                        }
                    } else {
                        channelsToRemove.addObject(channel as! AnyObject)
                    }
                }
                for channel in channelsToRemove {
                    self.subscribedChannels!.removeObjectForKey(channel)
                }
                // Clean messages buffer (can have lost message parts in memory)
                messagesBuffer!.removeAllObjects()
                OrtcClient.removeReceivedNotifications()
                self.delegateReconnectedCallback(self)
            } else {
                hasConnectedFirstTime = true
                self.delegateConnectedCallback(self)
            }
            self.startHeartbeatLoop()
        } else {
            self.disconnect()
            self.delegateExceptionCallback(self, error: self.generateError("Invalid connection"))
            
        }
        
    }
    
    static func removeReceivedNotifications(){
        if NSUserDefaults.standardUserDefaults().objectForKey(NOTIFICATIONS_KEY) != nil{
            let notificationsDict: NSMutableDictionary? = NSMutableDictionary(dictionary: (NSUserDefaults.standardUserDefaults().objectForKey(NOTIFICATIONS_KEY) as! NSMutableDictionary?)!)
            notificationsDict?.removeAllObjects()
            NSUserDefaults.standardUserDefaults().setObject(notificationsDict, forKey: NOTIFICATIONS_KEY)
            NSUserDefaults.standardUserDefaults().synchronize()
        }
    }
    
    func opSubscribed(message: String) {
        var subRegex: NSRegularExpression?
        do{
            subRegex = try NSRegularExpression(pattern: CHANNEL_PATTERN, options: NSRegularExpressionOptions.CaseInsensitive)
        }catch{
            
        }
        let subMatch: NSTextCheckingResult? = subRegex?.firstMatchInString(message, options: NSMatchingOptions.ReportProgress, range: NSMakeRange(0, (message as NSString).length))!
        if subMatch != nil {
            var channel: String?
            let strRangeChn: NSRange? = subMatch!.rangeAtIndex(1)
            if strRangeChn != nil {
                channel = (message as NSString).substringWithRange(strRangeChn!)
            }
            if channel != nil {
                let channelSubscription:ChannelSubscription = (self.subscribedChannels!.objectForKey(channel! as AnyObject) as? ChannelSubscription)!
                channelSubscription.isSubscribing = false
                channelSubscription.isSubscribed = true
                self.delegateSubscribedCallback(self, channel: channel!)
            }
        }
    }
    
    func opUnsubscribed(message: String) {
        var unsubRegex: NSRegularExpression?
        do{
            unsubRegex = try NSRegularExpression(pattern: CHANNEL_PATTERN, options: NSRegularExpressionOptions.CaseInsensitive)
        }catch{
            
        }
        let unsubMatch: NSTextCheckingResult? = unsubRegex?.firstMatchInString(message, options: NSMatchingOptions.ReportProgress, range: NSMakeRange(0, (message as NSString).length))
        if unsubMatch != nil {
            var channel: String?
            let strRangeChn: NSRange? = unsubMatch!.rangeAtIndex(1)
            if strRangeChn != nil {
                channel = (message as NSString).substringWithRange(strRangeChn!)
            }
            if channel != nil {
                self.subscribedChannels!.removeObjectForKey(channel! as NSString)
                self.delegateUnsubscribedCallback(self, channel: channel!)
            }
        }
        
    }
    
    func opException(message: String) {
        var exRegex: NSRegularExpression?
        
        do{
            exRegex = try NSRegularExpression(pattern: EXCEPTION_PATTERN, options:NSRegularExpressionOptions.CaseInsensitive)
        }catch{
            return
        }
        
        let exMatch: NSTextCheckingResult? = exRegex?.firstMatchInString(message, options: NSMatchingOptions.ReportProgress, range: NSMakeRange(0, (message as NSString).length))!
        if exMatch != nil {
            var operation: String?
            var channel: String?
            var error: String?
            let strRangeOp: NSRange? = exMatch!.rangeAtIndex(2)
            let strRangeChn: NSRange? = exMatch!.rangeAtIndex(4)
            let strRangeErr: NSRange? = exMatch!.rangeAtIndex(5)
            
            if strRangeOp!.location != NSNotFound{
                operation = (message as NSString).substringWithRange(strRangeOp!)
            }
            if strRangeChn!.location != NSNotFound{
                channel = (message as NSString).substringWithRange(strRangeChn!)
            }
            if strRangeErr!.location != NSNotFound{
                error = (message as NSString).substringWithRange(strRangeErr!)
            }
            if error != nil{
                if error == "Invalid connection." {
                    self.disconnect()
                }
                self.delegateExceptionCallback(self, error: self.generateError(error!))
            }
            if operation != nil {
                if errCases?.objectForKey(operation!) != nil {
                    switch (errCases?.objectForKey(operation!)as! NSNumber) {
                    case errCodes.errValidate.rawValue:
                        
                        isConnecting = false
                        isReconnecting = false
                        // Stop the connecting/reconnecting process
                        stopReconnecting = true
                        hasConnectedFirstTime = false
                        self.processDisconnect(false)
                        break
                    case errCodes.errSubscribe.rawValue:
                        if channel != nil && self.subscribedChannels!.objectForKey(channel!) != nil {
                            let channelSubscription:ChannelSubscription? = self.subscribedChannels!.objectForKey(channel!) as? ChannelSubscription
                            channelSubscription?.isSubscribing = false
                        }
                        break
                    case errCodes.errSendMaxSize.rawValue:
                        
                        if channel != nil && self.subscribedChannels?.objectForKey(channel!) != nil {
                            let channelSubscription:ChannelSubscription? = self.subscribedChannels!.objectForKey(channel!) as? ChannelSubscription
                            channelSubscription?.isSubscribing = false
                        }
                        // Stop the connecting/reconnecting process
                        stopReconnecting = true
                        hasConnectedFirstTime = false
                        self.disconnect()
                        break
                    default:
                        
                        break
                    }
                }
            }
        }
        
    }
    
    func opReceive(message: String) {
        var recRegex: NSRegularExpression?
        var recRegexFiltered: NSRegularExpression?
        
        do{
            recRegex = try NSRegularExpression(pattern: RECEIVED_PATTERN, options:NSRegularExpressionOptions.CaseInsensitive)
        }catch{
            
        }
        
        do{
            recRegexFiltered = try NSRegularExpression(pattern: RECEIVED_PATTERN_FILTERED, options:NSRegularExpressionOptions.CaseInsensitive)
        }catch{
            
        }
        
        let recMatch: NSTextCheckingResult? = recRegex?.firstMatchInString(message, options: NSMatchingOptions.ReportProgress, range: NSMakeRange(0, (message as NSString).length))
        let recMatchFiltered: NSTextCheckingResult? = recRegexFiltered?.firstMatchInString(message, options: NSMatchingOptions.ReportProgress, range: NSMakeRange(0, (message as NSString).length))
        
        if recMatch != nil{
            var aChannel: String?
            var aMessage: String?
            let strRangeChn: NSRange? = recMatch!.rangeAtIndex(1)
            let strRangeMsg: NSRange? = recMatch!.rangeAtIndex(2)
            if strRangeChn != nil {
                aChannel = (message as NSString).substringWithRange(strRangeChn!)
            }
            if strRangeMsg != nil {
                aMessage = (message as NSString).substringWithRange(strRangeMsg!)
            }
            if aChannel != nil && aMessage != nil {
                
                var msgRegex: NSRegularExpression?
                do{
                    msgRegex = try NSRegularExpression(pattern: MULTI_PART_MESSAGE_PATTERN, options:NSRegularExpressionOptions.CaseInsensitive)
                }catch{
                    
                }
                let multiMatch: NSTextCheckingResult? = msgRegex!.firstMatchInString(aMessage!, options: NSMatchingOptions.ReportProgress, range: NSMakeRange(0, (aMessage! as NSString).length))
                var messageId: String = ""
                var messageCurrentPart: Int32 = 1
                var messageTotalPart: Int32 = 1
                var lastPart: Bool = false
                if multiMatch != nil {
                    let strRangeMsgId: NSRange? = multiMatch!.rangeAtIndex(1)
                    let strRangeMsgCurPart: NSRange? = multiMatch!.rangeAtIndex(2)
                    let strRangeMsgTotPart: NSRange? = multiMatch!.rangeAtIndex(3)
                    let strRangeMsgRec: NSRange? = multiMatch!.rangeAtIndex(4)
                    if strRangeMsgId != nil {
                        messageId = (aMessage! as NSString).substringWithRange(strRangeMsgId!)
                    }
                    if strRangeMsgCurPart != nil {
                        messageCurrentPart = ((aMessage! as NSString).substringWithRange(strRangeMsgCurPart!) as NSString).intValue
                    }
                    if strRangeMsgTotPart != nil {
                        messageTotalPart = ((aMessage! as NSString).substringWithRange(strRangeMsgTotPart!) as NSString).intValue
                    }
                    if strRangeMsgRec != nil {
                        aMessage = (aMessage! as NSString).substringWithRange(strRangeMsgRec!)
                        //code below written by Rafa, gives a bug for a meesage containing % character
                        //aMessage = [[aMessage substringWithRange:strRangeMsgRec] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                    }
                }
                // Is a message part
                if self.isEmpty(messageId) == false {
                    if messagesBuffer?.objectForKey(messageId) == nil {
                        let msgSentDict: NSMutableDictionary = NSMutableDictionary()
                        msgSentDict["isMsgSent"] = NSNumber(bool: false)
                        messagesBuffer?.setObject(msgSentDict, forKey: messageId)
                    }
                    let messageBufferId: NSMutableDictionary? = messagesBuffer?.objectForKey(messageId) as? NSMutableDictionary
                    messageBufferId?.setObject(aMessage!, forKey: "\(messageCurrentPart)")
                    
                    if messageTotalPart == Int32(messageBufferId!.allKeys.count - 1) {
                        lastPart = true
                    }
                } else {
                    lastPart = true
                    
                }
                if lastPart {
                    if !self.isEmpty(messageId) {
                        aMessage = ""
                        let messageBufferId: NSMutableDictionary? = messagesBuffer?.objectForKey(messageId) as? NSMutableDictionary
                        for i in 1...messageTotalPart {
                            let messagePart: String? = messageBufferId?.objectForKey("\(i)") as? String
                            aMessage = aMessage! + messagePart!
                            // Delete from messages buffer
                            messageBufferId!.removeObjectForKey("\(i)")
                        }
                    }
                    if messagesBuffer?.objectForKey(messageId) != nil &&
                        messagesBuffer?.objectForKey(messageId)?.objectForKey("isMsgSent")?.boolValue == true {
                        messagesBuffer?.removeObjectForKey(messageId)
                    } else if self.subscribedChannels!.objectForKey(aChannel!) != nil {
                        let channelSubscription:ChannelSubscription? = self.subscribedChannels!.objectForKey(aChannel!) as? ChannelSubscription
                        if !self.isEmpty(messageId) {
                            let msgSentDict: NSMutableDictionary? = messagesBuffer?.objectForKey(messageId) as? NSMutableDictionary
                            msgSentDict?.setObject(NSNumber(bool: true), forKey: "isMsgSent")
                            messagesBuffer?.setObject(msgSentDict!, forKey: messageId)
                        }
                        aMessage = self.escapeRecvChars(aMessage! as NSString) as String
                        aMessage = self.checkForEmoji(aMessage! as NSString) as String
                        channelSubscription!.onMessage!(ortc: self, channel: aChannel!, message: aMessage!)
                    }
                }
            }
        } else if(recMatchFiltered != nil){
            var aChannel: String?
            var aMessage: String?
            var aFiltered: NSString?
            
            let strRangeChn: NSRange? = recMatchFiltered!.rangeAtIndex(1)
            let strRangeFiltered: NSRange? = recMatchFiltered!.rangeAtIndex(2)
            let strRangeMsg: NSRange? = recMatchFiltered!.rangeAtIndex(3)
            if strRangeChn != nil {
                aChannel = (message as NSString).substringWithRange(strRangeChn!)
            }
            if strRangeFiltered != nil {
                aFiltered = (message as NSString).substringWithRange(strRangeFiltered!)
            }
            if strRangeMsg != nil {
                aMessage = (message as NSString).substringWithRange(strRangeMsg!)
            }
            if aChannel != nil && aMessage != nil && aFiltered != nil {
                
                var msgRegex: NSRegularExpression?
                do{
                    msgRegex = try NSRegularExpression(pattern: MULTI_PART_MESSAGE_PATTERN, options:NSRegularExpressionOptions.CaseInsensitive)
                }catch{
                    
                }
                let multiMatch: NSTextCheckingResult? = msgRegex!.firstMatchInString(aMessage!, options: NSMatchingOptions.ReportProgress, range: NSMakeRange(0, (aMessage! as NSString).length))
                var messageId: String = ""
                var messageCurrentPart: Int32 = 1
                var messageTotalPart: Int32 = 1
                var lastPart: Bool = false
                if multiMatch != nil {
                    let strRangeMsgId: NSRange? = multiMatch!.rangeAtIndex(1)
                    let strRangeMsgCurPart: NSRange? = multiMatch!.rangeAtIndex(2)
                    let strRangeMsgTotPart: NSRange? = multiMatch!.rangeAtIndex(3)
                    let strRangeMsgRec: NSRange? = multiMatch!.rangeAtIndex(4)
                    if strRangeMsgId != nil {
                        messageId = (aMessage! as NSString).substringWithRange(strRangeMsgId!)
                    }
                    if strRangeMsgCurPart != nil {
                        messageCurrentPart = ((aMessage! as NSString).substringWithRange(strRangeMsgCurPart!) as NSString).intValue
                    }
                    if strRangeMsgTotPart != nil {
                        messageTotalPart = ((aMessage! as NSString).substringWithRange(strRangeMsgTotPart!) as NSString).intValue
                    }
                    if strRangeMsgRec != nil {
                        aMessage = (aMessage! as NSString).substringWithRange(strRangeMsgRec!)
                        //code below written by Rafa, gives a bug for a meesage containing % character
                        //aMessage = [[aMessage substringWithRange:strRangeMsgRec] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                    }
                }
                // Is a message part
                if self.isEmpty(messageId) == false {
                    if messagesBuffer?.objectForKey(messageId) == nil {
                        let msgSentDict: NSMutableDictionary = NSMutableDictionary()
                        msgSentDict["isMsgSent"] = NSNumber(bool: false)
                        messagesBuffer?.setObject(msgSentDict, forKey: messageId)
                    }
                    let messageBufferId: NSMutableDictionary? = messagesBuffer?.objectForKey(messageId) as? NSMutableDictionary
                    messageBufferId?.setObject(aMessage!, forKey: "\(messageCurrentPart)")
                    
                    if messageTotalPart == Int32(messageBufferId!.allKeys.count - 1) {
                        lastPart = true
                    }
                } else {
                    lastPart = true
                    
                }
                if lastPart {
                    if !self.isEmpty(messageId) {
                        aMessage = ""
                        let messageBufferId: NSMutableDictionary? = messagesBuffer?.objectForKey(messageId) as? NSMutableDictionary
                        for i in 1...messageTotalPart {
                            let messagePart: String? = messageBufferId?.objectForKey("\(i)") as? String
                            aMessage = aMessage! + messagePart!
                            // Delete from messages buffer
                            messageBufferId!.removeObjectForKey("\(i)")
                        }
                    }
                    if messagesBuffer?.objectForKey(messageId) != nil &&
                        messagesBuffer?.objectForKey(messageId)?.objectForKey("isMsgSent")?.boolValue == true {
                        messagesBuffer?.removeObjectForKey(messageId)
                    } else if self.subscribedChannels!.objectForKey(aChannel!) != nil {
                        let channelSubscription:ChannelSubscription? = self.subscribedChannels!.objectForKey(aChannel!) as? ChannelSubscription
                        if !self.isEmpty(messageId) {
                            let msgSentDict: NSMutableDictionary? = messagesBuffer?.objectForKey(messageId) as? NSMutableDictionary
                            msgSentDict?.setObject(NSNumber(bool: true), forKey: "isMsgSent")
                            messagesBuffer?.setObject(msgSentDict!, forKey: messageId)
                        }
                        aMessage = self.escapeRecvChars(aMessage! as NSString) as String
                        aMessage = self.checkForEmoji(aMessage! as NSString) as String
                        channelSubscription!.onMessageWithFilter!(ortc: self, channel: aChannel!, filtered: aFiltered!.boolValue, message: aMessage!)
                    }
                }
            }
        }
        
    }
    
    func checkForEmoji(var str:NSString)->String{
        var i = 0
        var len = str.length
        
        while i < len {
            let ascii:unichar = str.characterAtIndex(i)
            if(ascii == "\\".characterAtIndex(0)){
                
                let next = str.characterAtIndex(i + 1)
                
                if next == "u".characterAtIndex(0) {
                    var size = ((i - 1) + 12)
                    if (size < len && str.characterAtIndex(i + 6) == "u".characterAtIndex(0)){
                        var emoji: NSString? = str.substringWithRange(NSMakeRange((i), 12))
                        let pos: NSData? = emoji?.dataUsingEncoding(NSUTF8StringEncoding)
                        
                        if pos != nil{
                            emoji = NSString(data: pos!, encoding: NSNonLossyASCIIStringEncoding) as? String
                        }
                        if emoji != nil {
                            str = str.stringByReplacingCharactersInRange(NSMakeRange((i), 12), withString: emoji! as String)
                            
                        }
                        
                    }else{
                        var emoji: NSString? = str.substringWithRange(NSMakeRange((i), 6))
                        let pos: NSData? = emoji?.dataUsingEncoding(NSUTF8StringEncoding)
                        if pos != nil{
                            emoji = NSString(data: pos!, encoding: NSNonLossyASCIIStringEncoding) as? String
                        }
                        if emoji != nil {
                            str = str.stringByReplacingCharactersInRange(NSMakeRange((i), 6), withString: emoji! as String)
                        }
                    }
                }
            }
            len = str.length
            i = i + 1
        }
        return str as String
    }
    
    func escapeRecvChars(var str:NSString)->String{
        str = self.simulateJsonParse(str)
        str = self.simulateJsonParse(str)
        return str as String
    }
    
    func simulateJsonParse(str:NSString)->NSString{
        let ms: NSMutableString = NSMutableString()
        let len = str.length
        
        var i = 0
        while i < len {
            var ascii:unichar = str.characterAtIndex(i)
            if ascii > 128 {
                //unicode
                ms.appendFormat("%@",NSString(characters: &ascii, length: 1))
            } else {
                //ascii
                if ascii == "\\".characterAtIndex(0) {
                    i = i+1
                    let next = str.characterAtIndex(i)
                    
                    if next == "\\".characterAtIndex(0) {
                        ms.appendString("\\")
                    } else if next == "n".characterAtIndex(0) {
                        ms.appendString("\n")
                    } else if next == "\"".characterAtIndex(0) {
                        ms.appendString("\"")
                    } else if next == "b".characterAtIndex(0) {
                        ms.appendString("b")
                    } else if next == "f".characterAtIndex(0) {
                        ms.appendString("f")
                    } else if next == "r".characterAtIndex(0) {
                        ms.appendString("\r")
                    } else if next == "t".characterAtIndex(0) {
                        ms.appendString("\t")
                    } else if next == "u".characterAtIndex(0) {
                        ms.appendString("\\u")
                    }
                } else {
                    ms.appendFormat("%c",ascii)
                }
            }
            i = i + 1
        }
        return ms as NSString
    }
    
    func generateId(size: Int) -> String {
        let uuidRef: CFUUIDRef = CFUUIDCreate(nil)
        let uuidStringRef: CFStringRef = CFUUIDCreateString(nil, uuidRef)
        let uuid: NSString = NSString(string: uuidStringRef)
        return (uuid.stringByReplacingOccurrencesOfString("-", withString: "") as NSString).substringToIndex(size).lowercaseString
    }
    
    
    public func websocketDidConnect(socket: WebSocket){
        self.timer?.invalidate()
        if self.isEmpty(self.readLocalStorage(SESSION_STORAGE_NAME + applicationKey!)) {
            sessionId = self.generateId(16)
        }
        //Heartbeat details
        var hbDetails: String = ""
        if heartbeatActive == true{
            hbDetails = ";\(heartbeatTime!);\(heartbeatFails!);"
        }
        
        if connectionMetadata != nil {
            connectionMetadata = connectionMetadata!.replacingOccurrences(of: "\"", with: "\\\"") as NSString?
        }
        
        // Send validate
        let aString: String = "\"validate;\(applicationKey!);\(authenticationToken!);\(announcementSubChannel != nil ? announcementSubChannel! : "");\(sessionId != nil ? sessionId! : "");\(connectionMetadata != nil ? connectionMetadata! : "")\(hbDetails)\""
        self.webSocket!.writeString(aString)
    }
    
    public func websocketDidDisconnect(socket: WebSocket, error: NSError?){
        isConnecting = false
        // Reconnect
        if stopReconnecting == false {
            isConnecting = true
            stopReconnecting = false
            if isReconnecting == false {
                isReconnecting = true
                if isCluster == true {
                    let tUrl: NSURL? = NSURL(string: (clusterUrl as? String)!)
                    if (tUrl!.scheme == "http") && doFallback == true {
                        let t: NSString = clusterUrl!.stringByReplacingOccurrencesOfString("http:", withString: "https:")
                        let r: NSRange = t.rangeOfString("/server/ssl/")
                        if r.location == NSNotFound {
                            clusterUrl = t.stringByReplacingOccurrencesOfString("/server/", withString: "/server/ssl/")
                        }
                        else {
                            clusterUrl = t
                        }
                    }
                }
                self.doConnect(self)
            }
            else {
                dispatch_async(dispatch_get_main_queue(),{
                    self.timer = NSTimer.scheduledTimerWithTimeInterval(Double(self.connectionTimeout!), target: self, selector: "doConnect:", userInfo: nil, repeats: false)
                })
            }
        }
    }
    
    public func websocketDidReceiveMessage(socket: WebSocket, text: String){
        self.parseReceivedMessage(text)
    }
    
    public func websocketDidReceiveData(socket: WebSocket, data: NSData){
        
    }
    
    
    func parseReceivedNotifications(){
        
        if NSUserDefaults.standardUserDefaults().objectForKey(NOTIFICATIONS_KEY) != nil{
            let notificationsDict: NSMutableDictionary? = NSMutableDictionary(dictionary: NSUserDefaults.standardUserDefaults().objectForKey(NOTIFICATIONS_KEY) as! NSDictionary)
            
            if notificationsDict != nil && notificationsDict?.objectForKey(applicationKey!) != nil{
                
                let receivedMessages: NSMutableArray? = NSMutableArray(array: notificationsDict?.objectForKey(applicationKey!) as! NSArray)
                let receivedMCopy: NSMutableArray? = NSMutableArray(array:receivedMessages!)
                
                for message in receivedMCopy! {
                    self.parseReceivedMessage(message as? NSString)
                }
                receivedMessages!.removeAllObjects()
                notificationsDict!.setObject(receivedMessages!, forKey: applicationKey!)
                NSUserDefaults.standardUserDefaults().setObject(notificationsDict!, forKey: NOTIFICATIONS_KEY)
                NSUserDefaults.standardUserDefaults().synchronize()
            }
        }
    }
    
    func delegateConnectedCallback(ortc: OrtcClient) {
        self.ortcDelegate?.onConnected(ortc)
        self.parseReceivedNotifications()
    }
    
    func delegateDisconnectedCallback(ortc: OrtcClient) {
        self.ortcDelegate?.onDisconnected(ortc)
    }
    
    func delegateSubscribedCallback(ortc: OrtcClient, channel: String) {
        self.ortcDelegate?.onSubscribed(ortc, channel: channel)
    }
    
    func delegateUnsubscribedCallback(ortc: OrtcClient, channel: String) {
        self.ortcDelegate?.onUnsubscribed(ortc, channel: channel)
    }
    
    func delegateExceptionCallback(ortc: OrtcClient, error aError: NSError) {
        self.ortcDelegate?.onException(ortc, error: aError)
    }
    
    func delegateReconnectingCallback(ortc: OrtcClient) {
        self.ortcDelegate?.onReconnecting(ortc)
    }
    
    func delegateReconnectedCallback(ortc: OrtcClient) {
        self.ortcDelegate?.onReconnected(ortc)
    }
}


let WITH_NOTIFICATIONS = true
let WITHOUT_NOTIFICATIONS = false
let NOTIFICATIONS_KEY = "Local_Storage_Notifications"

class ChannelSubscription: NSObject {
    
    var isSubscribing: Bool?
    var isSubscribed: Bool?
    var subscribeOnReconnected: Bool?
    var withNotifications: Bool?
    var withFilter: Bool?
    var filter:String?
    var onMessage: ((ortc:OrtcClient, channel:String, message:String)->Void?)?
    var onMessageWithFilter: ((ortc:OrtcClient, channel:String, filtered:Bool, message:String)->Void?)?
    
    override init() {
        super.init()
    }
}

class PresenceRequest: NSObject {
    
    var isResponseJSON: Bool?
    var callback: ((error:NSError?, result:NSString?)->Void?)?
    var callbackDictionary: ((error:NSError?, result:NSDictionary?)->Void)?
    
    override init() {
        super.init()
    }
    
    func get(request: NSMutableURLRequest) {
        self.isResponseJSON = true
        self.processRequest(request)
    }
    
    func post(request: NSMutableURLRequest) {
        self.isResponseJSON = false
        self.processRequest(request)
    }
    
    func processRequest(request: NSMutableURLRequest){
        let ret:NSURLSessionDataTask? = NSURLSession.sharedSession().dataTaskWithRequest(request, completionHandler: { (data:NSData?, UrlResponse:NSURLResponse?, error:NSError?) -> Void in
            let dataStr: String? = String(data: data!, encoding: NSUTF8StringEncoding)
            if self.isResponseJSON == true && dataStr != nil {
                var dictionary: [NSObject : AnyObject]? = [NSObject : AnyObject]()
                do{
                    dictionary = try NSJSONSerialization.JSONObjectWithData(dataStr!.dataUsingEncoding(NSUTF8StringEncoding)!, options: NSJSONReadingOptions.MutableContainers) as? [NSObject : AnyObject]
                }catch{
                    if dataStr!.caseInsensitiveCompare("null") != NSComparisonResult.OrderedSame {
                        let errorDetail: NSMutableDictionary = NSMutableDictionary()
                        errorDetail.setObject(dataStr!, forKey: NSLocalizedDescriptionKey)
                        let error: NSError = NSError(domain:"OrtcClient", code: 1, userInfo: errorDetail as [NSObject : AnyObject])
                        self.callbackDictionary!(error: error, result: nil)
                    }
                    else {
                        self.callbackDictionary!(error:nil, result: ["null": "null"])
                    }
                    return
                }
                self.callbackDictionary!(error: nil, result: dictionary!)
            }else {
                self.callback!(error: nil, result: dataStr)
            }
        })
        if ret == nil {
            var errorDetail: [NSObject : AnyObject] = [NSObject : AnyObject]()
            errorDetail[NSLocalizedDescriptionKey] = "The connection can't be initialized."
            let error: NSError = NSError(domain:"OrtcClient", code: 1, userInfo: errorDetail)
            if self.isResponseJSON == true {
                self.callbackDictionary!(error: error, result: nil)
            }
            else {
                self.callback!(error: error, result: nil)
            }
        }else{
            ret!.resume()
        }
    }
}









