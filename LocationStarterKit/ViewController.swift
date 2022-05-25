//
//  ViewController.swift
//  LocationStarterKit
//
//  Created by Takamitsu Mizutori on 2016/08/12.
//  Copyright © 2016年 Goldrush Computing Inc. All rights reserved.
//

import UIKit
import MapKit

class GradientPolyline: MKPolyline {
    var hues: [CGFloat]?
    var widths: [CGFloat]?
    public func getHue(from index: Int) -> CGColor {
        return UIColor(hue: (hues?[index])!, saturation: 1, brightness: 1, alpha: 1).cgColor
    }
    public func getWidth(from index: Int) -> CGFloat {
        if let width = widths?[index] {
            return width
        } else {
            return CGFloat(1)
        }
    }
}

extension GradientPolyline {
    convenience init(locations: [CLLocation]) {
        let coordinates = locations.map( { $0.coordinate } )
        self.init(coordinates: coordinates, count: coordinates.count)

        let V_MAX = 3.0, V_MIN = 0.5, H_MAX = 0.3, H_MIN = 0.03
        let ACC_MAX = 50.0, ACC_MIN = 10.0, W_MAX = 2.0, W_MIN = 0.7
        
        hues = locations.map({
            let velocity: Double = $0.speed
            
            if velocity > V_MAX {
                return CGFloat(H_MAX)
            }

            if V_MIN <= velocity || velocity <= V_MAX {
                return CGFloat((H_MAX + ((velocity - V_MIN) * (H_MAX - H_MIN)) / (V_MAX - V_MIN)))
            }

            if velocity < V_MIN {
                return CGFloat(H_MIN)
            }

            return CGFloat(velocity)
        })
        
        widths = locations.map({
            let accuracy: Double = $0.horizontalAccuracy
            
            if accuracy > ACC_MAX {
                return CGFloat(W_MAX)
            }

            if ACC_MIN <= accuracy || accuracy <= ACC_MAX {
                return CGFloat((W_MAX + ((accuracy - ACC_MIN) * (W_MAX - W_MIN)) / (ACC_MAX - ACC_MIN)))
            }

            if accuracy < ACC_MIN {
                return CGFloat(W_MIN)
            }

            return CGFloat(1)
        })
        
    }
}

class GradientMKPolylineRenderer: MKPolylineRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        if(!mapRect.intersects(self.polyline.boundingMapRect)) {
            print("not intersecting, skipp")
            return
        }

        var prevColor: CGColor?
        var currentColor: CGColor?
        var currentWidth: CGFloat = 1

        guard let polyLine = self.polyline as? GradientPolyline else { return }

        for index in 0...self.polyline.pointCount - 1{
            let point = self.point(for: self.polyline.points()[index])
            let path = CGMutablePath()


            currentColor = polyLine.getHue(from: index)
            currentWidth = polyLine.getWidth(from: index)
            if index == 0 {
               path.move(to: point)
            } else {
                let prevPoint = self.point(for: self.polyline.points()[index - 1])
                path.move(to: prevPoint)
                path.addLine(to: point)

                let colors = [prevColor!, currentColor!] as CFArray
                let baseWidth = self.lineWidth * currentWidth / zoomScale

                context.saveGState()
                context.addPath(path)

                let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1])

                context.setLineWidth(baseWidth)
                context.replacePathWithStrokedPath()
                context.clip()
                context.drawLinearGradient(gradient!, start: prevPoint, end: point, options: [])
                context.restoreGState()
            }
            prevColor = currentColor
        }
    }
}


class ViewController: UIViewController, MKMapViewDelegate{
    
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
        
        self.accuracyRangeCircle = MKCircle(center: CLLocationCoordinate2D.init(latitude: 41.887, longitude: -87.622), radius: 50)
        self.mapView.addOverlay(self.accuracyRangeCircle!)
        
        
        self.didInitialZoom = false
        
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateMap(notification:)), name: Notification.Name(rawValue:"didUpdateLocation"), object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateKalmanSpeed(notification:)), name: Notification.Name(rawValue:"didUpdateKalmanLocation"), object: nil)
        
        
        NotificationCenter.default.addObserver(self, selector: #selector(showTurnOnLocationServiceAlert(notification:)), name: Notification.Name(rawValue:"showTurnOnLocationServiceAlert"), object: nil)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @objc func showTurnOnLocationServiceAlert(notification: NSNotification){
        let alert = UIAlertController(title: "Turn on Location Service", message: "To use location tracking feature of the app, please turn on the location service from the Settings app.", preferredStyle: .alert)
        
        let settingsAction = UIAlertAction(title: "Settings", style: .default) { (_) -> Void in
            let settingsUrl = URL(string: UIApplication.openSettingsURLString)
            if let url = settingsUrl {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        alert.addAction(settingsAction)
        alert.addAction(cancelAction)
        
        
        present(alert, animated: true, completion: nil)
        
    }
    
    @objc func updateMap(notification: NSNotification){
        if let userInfo = notification.userInfo{
            
            updatePolylines()

            if let newLocation = userInfo["location"] as? CLLocation{
                zoomTo(location: newLocation)
                if newLocation.speed > 0 {
                    gpsSpeedLable.text = String(format: "%.2f km/h", newLocation.speed * 3.6)
                } else {
                    gpsSpeedLable.text = String(format: "0 km/h")
                }
            }
            
        }
    }
    
    @objc func updateKalmanSpeed(notification: NSNotification){
        if let userInfo = notification.userInfo{
            if let newLocation = userInfo["location"] as? CLLocation{
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
            let polyLineRender = GradientMKPolylineRenderer(overlay: overlay)
            polyLineRender.lineWidth = 7
            return polyLineRender
        } else if overlay === self.accuracyRangeCircle{
            let circleRenderer = MKCircleRenderer(circle: overlay as! MKCircle)
            circleRenderer.fillColor = UIColor(white: 0.0, alpha: 0.25)
            circleRenderer.lineWidth = 0
            return circleRenderer
        } else {
            let polylineRenderer = MKPolylineRenderer(polyline: overlay as! MKPolyline)
            polylineRenderer.strokeColor = UIColor(rgb:0x1b60fe)
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
    
    func updatePolylines(){
        var locations: [CLLocation]?
        if kalmanEnabled {
            locations = LocationService.sharedInstance.LocationKalmanDataArray
        } else if filterEnabled {
            locations = LocationService.sharedInstance.locationFilteredDataArray
        } else {
            locations = LocationService.sharedInstance.locationRawDataArray
        }
        self.clearPolyline()
        
        let route = GradientPolyline(locations: locations!)
        self.polyline = route
        self.mapView.addOverlay(route)
    }
    
    func clearPolyline(){
        if self.polyline != nil{
            self.mapView.removeOverlay(self.polyline!)
            self.polyline = nil
        }
    }
    
    func zoomTo(location: CLLocation){
        if self.didInitialZoom == false{
            let coordinate = location.coordinate
            let region = MKCoordinateRegion.init(center: coordinate, latitudinalMeters: 300, longitudinalMeters: 300)
            self.mapView.setRegion(region, animated: false)
            self.didInitialZoom = true
        }
        
        if self.isBlockingAutoZoom == false{
            self.isZooming = true
            self.mapView.setCenter(location.coordinate, animated: true)
        }
        
        var accuracyRadius = 50.0
        if location.horizontalAccuracy > 0{
            if location.horizontalAccuracy > accuracyRadius{
                accuracyRadius = location.horizontalAccuracy
            }
        }
        
        self.mapView.removeOverlay(self.accuracyRangeCircle!)
        self.accuracyRangeCircle = MKCircle(center: location.coordinate, radius: accuracyRadius as CLLocationDistance)
        self.mapView.addOverlay(self.accuracyRangeCircle!)
        
        if self.userAnnotation != nil{
            self.mapView.removeAnnotation(self.userAnnotation!)
        }
        
        self.userAnnotation = UserAnnotation(coordinate: location.coordinate, title: "", subtitle: "")
        self.mapView.addAnnotation(self.userAnnotation!)
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation{
            return nil
        }else{
            let identifier = "UserAnnotation"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            if annotationView != nil{
                annotationView!.annotation = annotation
            }else{
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            }
            annotationView!.canShowCallout = false
            annotationView!.image = self.userAnnotationImage
            
            return annotationView
        }
    }
    
    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        if self.isZooming == true{
            self.isZooming = false
            self.isBlockingAutoZoom = false
        }else{
            self.isBlockingAutoZoom = true
            if let timer = self.zoomBlockingTimer{
                if timer.isValid{
                    timer.invalidate()
                }
            }
            self.zoomBlockingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false, block: { (Timer) in
                self.zoomBlockingTimer = nil
                self.isBlockingAutoZoom = false;
            })
        }
    }
    
    @IBAction func filterSwitchAction(_ sender: UISwitch) {
        if sender.isOn{
            filterEnabled = true
        }else{
            filterEnabled = false
        }
        updatePolylines()
    }
    
    @IBAction func kalmanSwitchAction(_ sender: UISwitch) {
        if sender.isOn{
            kalmanEnabled = true
        }else{
            kalmanEnabled = false
        }
        updatePolylines()
    }
    
}
