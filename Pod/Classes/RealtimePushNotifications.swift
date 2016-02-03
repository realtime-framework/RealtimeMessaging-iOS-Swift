//
//  RealtimePushNotifications.swift
//  OrtcClient
//
//  Created by joao caixinha on 21/01/16.
//  Copyright © 2016 Realtime. All rights reserved.
//

import Foundation
import UIKit

/**
 * OrtcClientPushNotificationsDelegate process custom push notification with payload
 */
public protocol OrtcClientPushNotificationsDelegate{

    /**
     * Process custom push notifications with payload.
     * If receive custom push and not declared in AppDelegate class trow's excpetion
     * - parameter channel: from witch channel the notification was send.
     * - parameter message: the remote notification title
     * - parameter payload: a dictionary containig the payload data
     */
    func onPushNotificationWithPayload(channel:String, message:String, payload:NSDictionary?)
}

/**
 * UIResponder extenssion for auto configure application to use remote notifications
 */
extension UIResponder: OrtcClientPushNotificationsDelegate{
    
/**
     Overrides UIResponder initialize method
*/
    override public class func initialize() {
        NSNotificationCenter.defaultCenter().addObserver(self.self, selector: "registForNotifications", name: UIApplicationDidFinishLaunchingNotification, object: nil)
    }
    
    @available(iOS, deprecated=1.0, message="For iOS older versions")
    static func registForNotifications() -> Bool {
        if UIApplication.sharedApplication().respondsToSelector("registerUserNotificationSettings:") {
            let settings: UIUserNotificationSettings = UIUserNotificationSettings(forTypes:[.Alert, .Badge, .Sound], categories: nil)
            UIApplication.sharedApplication().registerUserNotificationSettings(settings)
            UIApplication.sharedApplication().registerForRemoteNotifications()
        }
        else {
            UIApplication.sharedApplication().registerForRemoteNotificationTypes([.Sound, .Alert, .Badge])
        }
        return true
    }
    
    func application(application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: NSData) {
        var newToken: String = deviceToken.description
        newToken = newToken.stringByTrimmingCharactersInSet(NSCharacterSet(charactersInString: "<>"))
        newToken = newToken.stringByReplacingOccurrencesOfString(" ", withString: "")
        NSLog("\n\n - didRegisterForRemoteNotificationsWithDeviceToken:\n%@\n", deviceToken)
        OrtcClient.setDEVICE_TOKEN(newToken)
    }
    
    func application(application: UIApplication, didReceiveRemoteNotification userInfo: [NSObject : AnyObject], fetchCompletionHandler completionHandler: (UIBackgroundFetchResult) -> Void){
        completionHandler(UIBackgroundFetchResult.NewData)
        self.application(application, didReceiveRemoteNotification: userInfo)
    }
    
    func application(application: UIApplication, didReceiveRemoteNotification userInfo: [NSObject : AnyObject]) {
        if (userInfo["C"] as? NSString) != nil && (userInfo["M"] as? NSString) != nil && (userInfo["A"] as? NSString) != nil {
            if (((userInfo["aps"] as? NSDictionary)?["alert"]) is String) {
                let ortcMessage: String = "a[\"{\\\"ch\\\":\\\"\(userInfo["C"] as! String)\\\",\\\"m\\\":\\\"\(userInfo["M"] as! String)\\\"}\"]"
                
                var notificationsDict: NSMutableDictionary?
                if NSUserDefaults.standardUserDefaults().objectForKey(NOTIFICATIONS_KEY) != nil{
                     notificationsDict = NSMutableDictionary(dictionary: NSUserDefaults.standardUserDefaults().objectForKey(NOTIFICATIONS_KEY) as! NSDictionary)
                }
                if notificationsDict == nil {
                    notificationsDict = NSMutableDictionary()
                }
                
                var notificationsArray: NSMutableArray?
                
                if notificationsDict?.objectForKey(userInfo["A"] as! String) != nil{
                    notificationsArray = NSMutableArray(array: notificationsDict?.objectForKey(userInfo["A"] as! String) as! NSArray)
                }
                
                if notificationsArray == nil{
                    notificationsArray = NSMutableArray()
                }
                
                notificationsArray!.addObject(ortcMessage)
                notificationsDict!.setObject(notificationsArray!, forKey: (userInfo["A"] as! String))
                NSUserDefaults.standardUserDefaults().setObject(notificationsDict!, forKey: NOTIFICATIONS_KEY)
                NSUserDefaults.standardUserDefaults().synchronize()
                NSNotificationCenter.defaultCenter().postNotificationName("ApnsNotification", object: nil, userInfo: userInfo)
            }
            else if((UIApplication.sharedApplication().delegate?.respondsToSelector("onPushNotifications:message:payload:")) != nil){
                (UIApplication.sharedApplication().delegate as! UIResponder).onPushNotificationWithPayload(userInfo["C"] as! String,
                    message: userInfo["M"] as! String,
                    payload: userInfo["aps"] as? NSDictionary)
            }
        }
    }
    
    func application(application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: NSError) {
        NSLog("Failed to register with error : %@", error)
        NSNotificationCenter.defaultCenter().postNotificationName("ApnsRegisterError", object: nil, userInfo: [
            "ApnsRegisterError" : error
            ]
        )
    }
    
    /**
     * Process custom push notifications with payload.
     * If receive custom push and not declared in AppDelegate class trow's excpetion
     * - parameter channel: from witch channel the notification was send.
     * - parameter message: the remote notification title
     * - parameter payload: a dictionary containig the payload data
     */
    public func onPushNotificationWithPayload(channel:String, message:String, payload:NSDictionary?){
            preconditionFailure("Must override onPushNotificationWithPayload method on AppDelegate")
    }

}