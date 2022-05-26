//
//  LocationService.swift
//  LocationStarterKit
//
//  Created by Takamitsu Mizutori on 2016/08/12.
//  Copyright © 2016年 Goldrush Computing Inc. All rights reserved.
//

import CoreLocation
import UIKit

class EMA {
  private var lastUpdate: Date
  private var lastValue: Double
  private var delta: Double = 0.5
  private var tick: TimeInterval = 1

  init(date: Date, val: Double) {
    self.lastUpdate = date
    self.lastValue = val
  }

  init(date: Date, val: Double, tick: TimeInterval, delta: Double) {
    self.lastUpdate = date
    self.lastValue = val
    self.tick = tick
    self.delta = delta
  }

  func Predict(lastKnownVal: Double, lastKownTimestamp: Date) -> (
    predictedVal: Double, prediectionTimestamp: Date
  ) {
    if -lastKownTimestamp.timeIntervalSinceNow < self.tick {
      // can use the given data as the most fresh data
      let interval = lastKownTimestamp.timeIntervalSince1970 - self.lastUpdate.timeIntervalSince1970
      for _ in stride(from: 0, to: interval - self.tick, by: self.tick) {
        self.lastValue *= (1 - self.delta)
      }
      self.lastValue = lastKnownVal * self.delta + self.lastValue * (1 - self.delta)
      self.lastUpdate = lastKownTimestamp
    } else if lastKownTimestamp > self.lastUpdate {
      // the given data is old, but updatable
      // calculate from last update to last known
      let interval = lastKownTimestamp.timeIntervalSince1970 - self.lastUpdate.timeIntervalSince1970
      for _ in stride(from: 0, to: interval - self.tick, by: self.tick) {
        self.lastValue *= (1 - self.delta)
      }
      self.lastValue = lastKnownVal * self.delta + self.lastValue * (1 - self.delta)

      // calculate from last know to now
      let interval2 = -lastKownTimestamp.timeIntervalSinceNow
      for _ in stride(from: 0, to: interval2 - self.tick, by: self.tick) {
        self.lastValue *= (1 - self.delta)
      }
      self.lastUpdate = Date()
    } else {
      // dispose the given data
      let interval = -self.lastUpdate.timeIntervalSinceNow
      for _ in stride(from: 0, to: interval - self.tick, by: self.tick) {
        self.lastValue *= (1 - self.delta)
      }
      self.lastUpdate = Date()
    }

    return (self.lastValue, self.lastUpdate)
  }
}

public class LocationService: NSObject, CLLocationManagerDelegate {
  var resetKalmanFilter: Bool = false

  var ema: EMA?

  public static var sharedInstance = LocationService()
  let locationManager: CLLocationManager
  var locationRawDataArray: [CLLocation]
  var locationFilteredDataArray: [CLLocation]

  override init() {
    locationManager = CLLocationManager()

    locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    locationManager.distanceFilter = 0

    locationManager.requestWhenInUseAuthorization()
    locationManager.allowsBackgroundLocationUpdates = true
    locationManager.pausesLocationUpdatesAutomatically = false
    locationRawDataArray = [CLLocation]()
    locationFilteredDataArray = [CLLocation]()

    super.init()

    locationManager.delegate = self

  }

  func startUpdatingLocation() {
    if CLLocationManager.locationServicesEnabled() {
      locationManager.startUpdatingLocation()
    } else {
      //tell view controllers to show an alert
      showTurnOnLocationServiceAlert()
    }
  }

  //MARK: CLLocationManagerDelegate protocol methods
  public func locationManager(
    _ manager: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    for newLocation in locations {
      locationRawDataArray.append(newLocation)
      if filterAndAddLocation(newLocation) {
        var lastSpeed = newLocation.speed < 0 ? 0 : newLocation.speed
        // if last update is too old, then 0
        lastSpeed = -newLocation.timestamp.timeIntervalSinceNow > 5 ? 0 : lastSpeed
        if self.ema == nil {
          self.ema = EMA(date: newLocation.timestamp, val: lastSpeed, tick: 2, delta: 0.9)
        }
        let prediction = self.ema!.Predict(
          lastKnownVal: lastSpeed, lastKownTimestamp: newLocation.timestamp)
        let filteredSpeed = prediction.predictedVal
        let predictionTimestamp = prediction.prediectionTimestamp
        let filteredLocation = CLLocation(
          coordinate: newLocation.coordinate, altitude: newLocation.altitude,
          horizontalAccuracy: newLocation.horizontalAccuracy,
          verticalAccuracy: newLocation.verticalAccuracy, course: newLocation.speed,
          courseAccuracy: newLocation.courseAccuracy, speed: filteredSpeed,
          speedAccuracy: newLocation.speedAccuracy, timestamp: predictionTimestamp)
        locationFilteredDataArray.append(filteredLocation)
        self.notifyUpdateFilteredLocaiont(newLocation: filteredLocation)
      }
    }
    if let lastLocation = locations.last {
      notifiyDidUpdateLocation(newLocation: lastLocation)
    }
  }

  func filterAndAddLocation(_ location: CLLocation) -> Bool {
    let age = -location.timestamp.timeIntervalSinceNow

    if age > 10 {
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

  public func locationManager(
    _ manager: CLLocationManager,
    didFailWithError error: Error
  ) {
    if (error as NSError).domain == kCLErrorDomain
      && (error as NSError).code == CLError.Code.denied.rawValue
    {
      //User denied your app access to location information.
      showTurnOnLocationServiceAlert()
    }
  }

  public func locationManager(
    _ manager: CLLocationManager,
    didChangeAuthorization status: CLAuthorizationStatus
  ) {
    if status == .authorizedWhenInUse {
      //You can resume logging by calling startUpdatingLocation here
    }
  }

  func showTurnOnLocationServiceAlert() {
    NotificationCenter.default.post(
      name: Notification.Name(rawValue: "showTurnOnLocationServiceAlert"), object: nil)
  }

  func notifiyDidUpdateLocation(newLocation: CLLocation) {
    NotificationCenter.default.post(
      name: Notification.Name(rawValue: "didUpdateLocation"), object: nil,
      userInfo: ["location": newLocation])
  }

  func notifyUpdateFilteredLocaiont(newLocation: CLLocation) {
    NotificationCenter.default.post(
      name: Notification.Name(rawValue: "didUpdateFilteredLocation"), object: nil,
      userInfo: ["location": newLocation])
  }
}
