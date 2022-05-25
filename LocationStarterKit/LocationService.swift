//
//  LocationService.swift
//  LocationStarterKit
//
//  Created by Takamitsu Mizutori on 2016/08/12.
//  Copyright © 2016年 Goldrush Computing Inc. All rights reserved.
//

import UIKit
import CoreLocation

public class LocationService: NSObject, CLLocationManagerDelegate{
    var resetKalmanFilter: Bool = false
    var hcKalmanFilter: HCKalmanAlgorithm?

    public static var sharedInstance = LocationService()
    let locationManager: CLLocationManager
    var locationRawDataArray: [CLLocation]
    var locationFilteredDataArray: [CLLocation]
    var LocationKalmanDataArray: [CLLocation]

    override init() {
        locationManager = CLLocationManager()
        
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 0
        
        locationManager.requestWhenInUseAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationRawDataArray = [CLLocation]()
        locationFilteredDataArray = [CLLocation]()
        LocationKalmanDataArray = [CLLocation]()
        
        super.init()
        
        locationManager.delegate = self
        
        
    }
    
    
    func startUpdatingLocation(){
        if CLLocationManager.locationServicesEnabled(){
            locationManager.startUpdatingLocation()
        }else{
            //tell view controllers to show an alert
            showTurnOnLocationServiceAlert()
        }
    }
    
    
    //MARK: CLLocationManagerDelegate protocol methods
    public func locationManager(_ manager: CLLocationManager,
                                  didUpdateLocations locations: [CLLocation]){
        var kalmanFilteredLast: CLLocation?
        for newLocation in locations {
            locationRawDataArray.append(newLocation)
            if filterAndAddLocation(newLocation) {
                locationFilteredDataArray.append(newLocation)
                if hcKalmanFilter == nil {
                    print("kalman: inited")
                    hcKalmanFilter = HCKalmanAlgorithm(initialLocation: newLocation)
                } else {
                    let kalmanLocation = hcKalmanFilter!.processState(currentLocation: newLocation)
                    print("kalman:", kalmanLocation)
                    kalmanFilteredLast = kalmanLocation
                    LocationKalmanDataArray.append(kalmanLocation)
                    print(kalmanLocation)
                }
            }
        }
        if let lastLocation = locations.last {
            notifiyDidUpdateLocation(newLocation: lastLocation)
        }
        
        if let kaledLocation = kalmanFilteredLast {
            notifiyDidUpdateKalmanLocation(newLocation: kaledLocation)
        }
    }
    
    func filterAndAddLocation(_ location: CLLocation) -> Bool{
        let age = -location.timestamp.timeIntervalSinceNow
        
        if age > 10{
            print("Locaiton is old.")
            return false
        }
        
        if location.horizontalAccuracy < 0 {
            print("Latitidue and longitude values are invalid.")
            return false
        }
        
        if location.horizontalAccuracy > 50 {
            print("Accuracy is too low.")
            return false
        }
        
        print("Location quality is good enough.")
        return true
        
    }
    
    
    public func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error){
        if (error as NSError).domain == kCLErrorDomain && (error as NSError).code == CLError.Code.denied.rawValue{
            //User denied your app access to location information.
            showTurnOnLocationServiceAlert()
        }
    }
    
    public func locationManager(_ manager: CLLocationManager,
                                  didChangeAuthorization status: CLAuthorizationStatus){
        if status == .authorizedWhenInUse{
            //You can resume logging by calling startUpdatingLocation here
        }
    }
    
    func showTurnOnLocationServiceAlert(){
        NotificationCenter.default.post(name: Notification.Name(rawValue:"showTurnOnLocationServiceAlert"), object: nil)
    }    
    
    func notifiyDidUpdateLocation(newLocation:CLLocation){
        NotificationCenter.default.post(name: Notification.Name(rawValue:"didUpdateLocation"), object: nil, userInfo: ["location" : newLocation])        
    }
    
    func notifiyDidUpdateKalmanLocation(newLocation:CLLocation){
        NotificationCenter.default.post(name: Notification.Name(rawValue:"didUpdateKalmanLocation"), object: nil, userInfo: ["location" : newLocation])
    }
}

