//
//  ViewController.swift
//  LocationStarterKit
//
//  Created by Takamitsu Mizutori on 2016/08/12.
//  Copyright © 2016年 Goldrush Computing Inc. All rights reserved.
//

import MapKit
import UIKit

let M2KM = 3.6

class GradientPolyline: MKPolyline {
  var hues: [CGFloat]?
  public func getHue(from index: Int) -> CGColor {
    return UIColor(hue: (hues?[index])!, saturation: 1, brightness: 1, alpha: 1).cgColor
  }
}

extension GradientPolyline {
  convenience init(locations: [CLLocation], v_min: Double = 3.0, v_max: Double = 7.0) {
    let coordinates = locations.map({ $0.coordinate })
    self.init(coordinates: coordinates, count: coordinates.count)

    // in range
    let V_RANGE_MIN = v_min / M2KM  // 3.0 / M2KM
    let V_RANGE_MAX = v_max / M2KM  // 7.0 / M2KM
    let HUE_RANGE_MIN = 180.0 / 360.0  // 60.0 / 360.0
    let HUE_RANGE_MAX = 60.0 / 360.0  // 180.0 / 360.0
    // out of range
    let half_range = (V_RANGE_MAX - V_RANGE_MIN) / 2.0

    let V_MIN = V_RANGE_MIN - half_range
    let V_MAX = V_RANGE_MAX + half_range

    let HUE_MIN = 240.0 / 360.0
    let HUE_MAX = 0.0

    hues = locations.map({
      let velocity: Double = $0.speed

      if velocity >= V_MAX {
        return CGFloat(HUE_MAX)
      } else if velocity <= V_MIN {
        return CGFloat(HUE_MIN)
      } else if velocity >= V_RANGE_MAX {
        // from hue_range_max to hue_max
        return CGFloat(
          HUE_RANGE_MAX + (velocity - V_RANGE_MAX) * (HUE_MAX - HUE_RANGE_MAX)
            / (V_MAX - V_RANGE_MAX))
      } else if velocity <= V_RANGE_MIN {
        // from hue_min to hue_range_min
        return CGFloat(
          HUE_MIN + (velocity - V_MIN) * (HUE_RANGE_MIN - HUE_MIN)
            / (V_RANGE_MIN - V_MIN))
      }
      return CGFloat(
        HUE_RANGE_MIN + (velocity - V_RANGE_MIN) * (HUE_RANGE_MAX - HUE_RANGE_MIN)
          / (V_RANGE_MAX - V_RANGE_MIN))
    })

  }
}

class GradientMKPolylineRenderer: MKPolylineRenderer {
  /// If a border should be rendered to make the line more visible
  var showsBorder: Bool = false
  /// The color of tne border, if showsBorder is true
  var borderColor: CGColor = {
    let space = CGColorSpace(name: CGColorSpace.genericRGBLinear)!
    let comps: [CGFloat] = [1, 1, 1, 1]
    let color = CGColor(colorSpace: space, components: comps)!
    return color
  }()

  init(polyline: GradientPolyline, showsBorder: Bool, borderColor: CGColor) {
    self.showsBorder = showsBorder
    self.borderColor = borderColor
    super.init(overlay: polyline)
  }

  init(polyline: GradientPolyline) {
    super.init(overlay: polyline)
  }

  override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
    if !mapRect.intersects(self.polyline.boundingMapRect) {
      print("not intersecting, skipp")
      return
    } else if polyline.pointCount < 2 {
      return
    }

    let baseWidth: CGFloat = self.lineWidth / zoomScale

    if self.showsBorder {
      context.setLineWidth(baseWidth * 2)
      context.setLineJoin(CGLineJoin.round)
      context.setLineCap(CGLineCap.round)
      context.addPath(self.path)
      context.setStrokeColor(self.borderColor)
      context.strokePath()
    }

    /*
         Define path properties and add it to context
         */

    /*
         Replace path with stroked version so we can clip
         */
    context.saveGState()

    context.replacePathWithStrokedPath()
    context.clip()

    let gradientPolyline = polyline as! GradientPolyline

    for index in 1...self.polyline.pointCount - 1 {
      let currentPoint = self.point(for: self.polyline.points()[index])
      let prevPoint = self.point(for: self.polyline.points()[index - 1])
      let currentColor = gradientPolyline.getHue(from: index)
      let prevColor = gradientPolyline.getHue(from: index - 1)
      let path = CGMutablePath()

      path.move(to: prevPoint)
      path.addLine(to: currentPoint)

      let colors = [prevColor, currentColor] as CFArray

      context.saveGState()
      context.addPath(path)

      let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1])

      context.setLineWidth(baseWidth)
      context.setLineJoin(CGLineJoin.round)
      context.setLineCap(CGLineCap.round)

      context.replacePathWithStrokedPath()
      context.clip()
      context.drawLinearGradient(gradient!, start: prevPoint, end: currentPoint, options: [])
      context.restoreGState()
    }
  }

  /*
     Create path from polyline
     Thanks to Adrian Schoenig
     (http://adrian.schoenig.me/blog/2013/02/21/drawing-multi-coloured-lines-on-an-mkmapview/ )
     */
  public override func createPath() {
    let path: CGMutablePath = CGMutablePath()
    var pathIsEmpty: Bool = true

    for i in 0...self.polyline.pointCount - 1 {

      let point: CGPoint = self.point(for: self.polyline.points()[i])
      if pathIsEmpty {
        path.move(to: point)
        pathIsEmpty = false
      } else {
        path.addLine(to: point)
      }
    }
    self.path = path
  }
}

class ViewController: UIViewController, MKMapViewDelegate {

  @IBOutlet var mapView: MKMapView!
  @IBOutlet var gpsSpeedLable: UILabel!
  @IBOutlet var filteredSpeedLable: UILabel!
  var userAnnotationImage: UIImage?
  var userAnnotation: UserAnnotation?
  var accuracyRangeCircle: MKCircle?
  var polyline: GradientPolyline?
  var isZooming: Bool?
  var isBlockingAutoZoom: Bool?
  var zoomBlockingTimer: Timer?
  var didInitialZoom: Bool?
  var filterEnabled: Bool = false
  var kalmanEnabled: Bool = false

  override func viewDidLoad() {
    super.viewDidLoad()

    self.mapView.delegate = self
    self.mapView.showsUserLocation = false

    self.userAnnotationImage = UIImage(named: "user_position_ball")!

    self.accuracyRangeCircle = MKCircle(
      center: CLLocationCoordinate2D.init(latitude: 41.887, longitude: -87.622), radius: 50)
    self.mapView.addOverlay(self.accuracyRangeCircle!)

    self.didInitialZoom = false

    NotificationCenter.default.addObserver(
      self, selector: #selector(updateMap(notification:)),
      name: Notification.Name(rawValue: "didUpdateLocation"), object: nil)

    NotificationCenter.default.addObserver(
      self, selector: #selector(updateKalmanSpeed(notification:)),
      name: Notification.Name(rawValue: "didUpdateKalmanLocation"), object: nil)

    NotificationCenter.default.addObserver(
      self, selector: #selector(showTurnOnLocationServiceAlert(notification:)),
      name: Notification.Name(rawValue: "showTurnOnLocationServiceAlert"), object: nil)
  }

  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }

  @objc func showTurnOnLocationServiceAlert(notification: NSNotification) {
    let alert = UIAlertController(
      title: "Turn on Location Service",
      message:
        "To use location tracking feature of the app, please turn on the location service from the Settings app.",
      preferredStyle: .alert)

    let settingsAction = UIAlertAction(title: "Settings", style: .default) { (_) -> Void in
      let settingsUrl = URL(string: UIApplication.openSettingsURLString)
      if let url = settingsUrl {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
      }
    }

    let cancelAction = UIAlertAction(
      title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
    alert.addAction(settingsAction)
    alert.addAction(cancelAction)

    present(alert, animated: true, completion: nil)

  }

  @objc func updateMap(notification: NSNotification) {
    if let userInfo = notification.userInfo {

      updatePolylines()

      if let newLocation = userInfo["location"] as? CLLocation {
        zoomTo(location: newLocation)
        if newLocation.speed > 0 {
          gpsSpeedLable.text = String(format: "%.2f km/h", newLocation.speed * 3.6)
        } else {
          gpsSpeedLable.text = String(format: "0 km/h")
        }
      }

    }
  }

  @objc func updateKalmanSpeed(notification: NSNotification) {
    if let userInfo = notification.userInfo {
      if let newLocation = userInfo["location"] as? CLLocation {
        if newLocation.speed > 0 {
          filteredSpeedLable.text = String(format: "%.2f km/h", newLocation.speed * 3.6)
        } else {
          filteredSpeedLable.text = String(format: "0 km/h")
        }

      }

    }
  }

  func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
    if overlay is GradientPolyline {
      let polyLineRender = GradientMKPolylineRenderer(
        polyline: overlay as! GradientPolyline, showsBorder: true,
        borderColor: UIColor.black.cgColor)
      polyLineRender.lineWidth = 7
      return polyLineRender
    } else if overlay === self.accuracyRangeCircle {
      let circleRenderer = MKCircleRenderer(circle: overlay as! MKCircle)
      circleRenderer.fillColor = UIColor(white: 0.0, alpha: 0.25)
      circleRenderer.lineWidth = 0
      return circleRenderer
    } else {
      let polylineRenderer = MKPolylineRenderer(polyline: overlay as! MKPolyline)
      polylineRenderer.strokeColor = UIColor(rgb: 0x1b60fe)
      polylineRenderer.alpha = 0.5
      polylineRenderer.lineWidth = 5.0
      return polylineRenderer
    }
  }

  //    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
  //
  //        if overlay === self.accuracyRangeCircle{
  //            let circleRenderer = MKCircleRenderer(circle: overlay as! MKCircle)
  //            circleRenderer.fillColor = UIColor(white: 0.0, alpha: 0.25)
  //            circleRenderer.lineWidth = 0
  //            return circleRenderer
  //        }else{
  //            let polylineRenderer = MKPolylineRenderer(polyline: overlay as! MKPolyline)
  //            polylineRenderer.strokeColor = UIColor(rgb:0x1b60fe)
  //            polylineRenderer.alpha = 0.5
  //            polylineRenderer.lineWidth = 5.0
  //            return polylineRenderer
  //        }
  //    }

  func updatePolylines() {
    var locations: [CLLocation]?
    if kalmanEnabled {
      locations = LocationService.sharedInstance.LocationKalmanDataArray
    } else if filterEnabled {
      locations = LocationService.sharedInstance.locationFilteredDataArray
    } else {
      locations = LocationService.sharedInstance.locationRawDataArray
    }
    self.clearPolyline()

    let route = GradientPolyline(locations: locations!, v_min: 7.0, v_max: 14.0)
    self.polyline = route
    self.mapView.addOverlay(route)
  }

  func clearPolyline() {
    if self.polyline != nil {
      self.mapView.removeOverlay(self.polyline!)
      self.polyline = nil
    }
  }

  func zoomTo(location: CLLocation) {
    if self.didInitialZoom == false {
      let coordinate = location.coordinate
      let region = MKCoordinateRegion.init(
        center: coordinate, latitudinalMeters: 300, longitudinalMeters: 300)
      self.mapView.setRegion(region, animated: false)
      self.didInitialZoom = true
    }

    if self.isBlockingAutoZoom == false {
      self.isZooming = true
      self.mapView.setCenter(location.coordinate, animated: true)
    }

    var accuracyRadius = 50.0
    if location.horizontalAccuracy > 0 {
      if location.horizontalAccuracy > accuracyRadius {
        accuracyRadius = location.horizontalAccuracy
      }
    }

    self.mapView.removeOverlay(self.accuracyRangeCircle!)
    self.accuracyRangeCircle = MKCircle(
      center: location.coordinate, radius: accuracyRadius as CLLocationDistance)
    self.mapView.addOverlay(self.accuracyRangeCircle!)

    if self.userAnnotation != nil {
      self.mapView.removeAnnotation(self.userAnnotation!)
    }

    self.userAnnotation = UserAnnotation(coordinate: location.coordinate, title: "", subtitle: "")
    self.mapView.addAnnotation(self.userAnnotation!)
  }

  func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    if annotation is MKUserLocation {
      return nil
    } else {
      let identifier = "UserAnnotation"
      var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
      if annotationView != nil {
        annotationView!.annotation = annotation
      } else {
        annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
      }
      annotationView!.canShowCallout = false
      annotationView!.image = self.userAnnotationImage

      return annotationView
    }
  }

  func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
    if self.isZooming == true {
      self.isZooming = false
      self.isBlockingAutoZoom = false
    } else {
      self.isBlockingAutoZoom = true
      if let timer = self.zoomBlockingTimer {
        if timer.isValid {
          timer.invalidate()
        }
      }
      self.zoomBlockingTimer = Timer.scheduledTimer(
        withTimeInterval: 10.0, repeats: false,
        block: { (Timer) in
          self.zoomBlockingTimer = nil
          self.isBlockingAutoZoom = false
        })
    }
  }

  @IBAction func filterSwitchAction(_ sender: UISwitch) {
    if sender.isOn {
      filterEnabled = true
    } else {
      filterEnabled = false
    }
    updatePolylines()
  }

  @IBAction func kalmanSwitchAction(_ sender: UISwitch) {
    if sender.isOn {
      kalmanEnabled = true
    } else {
      kalmanEnabled = false
    }
    updatePolylines()
  }

}
