//
//  Balancer
//
//  Balancer.swift
//  Balancer
//
//  Created by João Caixinha.
//
//
import Foundation

let BALANCER_RESPONSE_PATTERN: String = "^var SOCKET_SERVER = \\\"(.*?)\\\";$"


/**
 * Request's balancer for connection url
 */
class Balancer: NSObject {
    var theCallabck: ((String?) -> ())?
    
    init(cluster aCluster: String?, serverUrl url: String?, isCluster: Bool?, appKey anAppKey: String?, callback aCallback: (aBalancerResponse: String?) -> Void) {
        super.init()
        theCallabck = aCallback
        var parsedUrl: String? = aCluster
        if isCluster == false {
            aCallback(aBalancerResponse: url)
        }
        else {
            parsedUrl = parsedUrl?.stringByAppendingString("?appkey=")
            parsedUrl = parsedUrl?.stringByAppendingString(anAppKey!)
            let request: NSURLRequest = NSURLRequest(URL: NSURL(string: parsedUrl!)!)
            NSURLSession.sharedSession().dataTaskWithRequest(request, completionHandler: {
                (receivedData:NSData?, response:NSURLResponse?, error:NSError?) -> Void in
                if error != nil{
                    self.theCallabck!(nil)
                    return
                }
                else if receivedData != nil {
                    do{
                        let myString: NSString? = String(data: receivedData!, encoding: NSUTF8StringEncoding)
                        let resRegex: NSRegularExpression = try NSRegularExpression(pattern: BALANCER_RESPONSE_PATTERN, options: NSRegularExpressionOptions.CaseInsensitive)
                        let resMatch: NSTextCheckingResult? = resRegex.firstMatchInString(myString! as String, options: NSMatchingOptions.ReportProgress, range: NSMakeRange(0, myString!.length))
                    
                        if resMatch != nil {
                            let strRange: NSRange? = resMatch!.rangeAtIndex(1)
                            if strRange != nil && strRange?.length <= myString?.length {
                                self.theCallabck!(myString!.substringWithRange(strRange!) as String)
                                return
                            }
                        }
                    }catch{
                        self.theCallabck!(nil)
                        return
                    }
                }
                self.theCallabck!(nil)
            }).resume()
            
        }
    }
}
    