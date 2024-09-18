import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';

/*
Terra Bearing: Advanced Bearing Measurement Application

Purpose:
This application is designed for outdoor enthusiasts, surveyors, and navigation professionals
who require precise compass calibration and bearing measurements. It combines GPS, magnetometer,
and accelerometer data to provide accurate directional information, especially useful in areas
with magnetic anomalies or when using devices with varying magnetic sensors. It also allows to 
triangulate bearings between two points on the map so that users can identify features (e.g.,
mountains, buildings, trees) on the terrain.

Key Functionalities:
1. Real-time compass display with offset calibration
2. GPS-based location tracking and map integration
3. Bearing measurement and visual marking on the map
4. Advanced compass calibration process
5. Toggleable map orientation (North-up vs. Heading-up)
6. Multiple map layer options (Normal, Satellite, Terrain, Hybrid)
7. Camera view integration for visual alignment during measurements
8. Tilt detection for optimal device positioning

Main Classes:
1. MyApp: The root widget of the application, sets up the app theme and initial route.
2. MapScreen: The primary stateful widget that contains the main UI and logic.
3. _MapScreenState: Manages the state and implements the core functionality of the app.
4. CrosshairPainter: A custom painter for drawing the crosshair overlay.

Key State Variables and Their Purposes:
- _currentPosition (LatLng): Stores the current GPS location of the device.
- _currentBearing (double): Holds the current compass bearing.
- _compassOffset (double): Stores the calibration offset for the compass.
- _isMapOrientedToNorth (bool): Tracks whether the map is oriented to north or the current heading.
- _isHeadingActive (bool): Indicates if the real-time heading line is being displayed.
- _isCalibrating (bool): Flags whether the app is currently in calibration mode.
- _polylines (Set<Polyline>): Stores all polylines drawn on the map (headings, calibration lines).
- _referenceMarker (Marker): Represents a user-placed reference point on the map.
- _calibrationMarker1 and _calibrationMarker2 (Marker): Used during the calibration process.
- _initialCalibrationHeading (double): Stores the initial heading during calibration.
- _cameraController (CameraController): Manages the device's camera for the overlay view.
- _isTilted (bool): Indicates whether the device is tilted beyond a certain threshold.

Main Logic Flow:
1. The app initializes by setting up location services, compass listening, and camera.
2. It continuously updates the current position and bearing as the user moves.
3. Users can mark bearings, which are displayed as lines on the map.
4. The calibration process involves setting two points and aligning the device to calculate offset.
5. Map orientation and type can be changed through the UI controls.
6. The app detects device tilt and displays a camera view for alignment when tilted significantly.

This application serves as a comprehensive tool for accurate bearing measurements and
compass calibration, suitable for both professional use and outdoor enthusiasts requiring
precise navigation information.
*/

// Main entry point of the application
void main() => runApp(MyApp());

// Root widget of the application
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      title: 'Terra Bearing',
      theme: CupertinoThemeData(
        primaryColor: CupertinoColors.activeBlue,
      ),
      home: MapScreen(),
    );
  }
}

// Main screen widget containing the map and compass functionality
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  _MapScreenState createState() => _MapScreenState();
}

// State class for the MapScreen
class _MapScreenState extends State<MapScreen> {
  // Various state variables for managing map, location, and compass data
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  final Location _location = Location();
  final Set<Polyline> _polylines = <Polyline>{};
  double? _currentBearing;
  double _compassOffset = 0.0;
  bool _isMapOrientedToNorth = true;
  bool _isHeadingActive = true;
  bool _isCalibrating = false;
  bool _wasHeadingActive = false;
  int _selectedIndex = 0;
  Polyline? _headingLine;
  String _topBarText = "";
  MapType _currentMapType = MapType.normal;
  Marker? _referenceMarker;
  Marker? _calibrationMarker1;
  Marker? _calibrationMarker2;
  Polyline? _calibrationLine;
  String _calibrationButtonText = "Calibrate: phone aligned";
  double? _initialCalibrationHeading;
  CameraController? _cameraController;
  bool _isTilted = false;

  @override
  void initState() {
    super.initState();
    // Initialize various components of the app
    _getLocationPermission();
    _startCompass();
    _listenToLocationChanges();
    _initializeCamera();
    _listenToAccelerometer();
  }

  // Initialize the device camera
  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isNotEmpty) {
      _cameraController = CameraController(cameras.first, ResolutionPreset.max);
      try {
        await _cameraController!.initialize();
        setState(() {}); // Trigger a rebuild after camera is initialized
      } catch (e) {
        print("Error initializing camera: $e");
      }
    }
  }

  // Listen to accelerometer events to detect device tilt
  void _listenToAccelerometer() {
    accelerometerEventStream().listen((AccelerometerEvent event) {
      double tiltAngle = atan2(event.y, event.z) * (180 / pi);
      bool newTiltState = tiltAngle.abs() > 70;
      if (newTiltState != _isTilted) {
        setState(() {
          _isTilted = newTiltState;
        });
      }
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  // Listen to location changes and update the current position
  void _listenToLocationChanges() {
    _location.onLocationChanged.listen((locationData) {
      if (locationData.latitude != null && locationData.longitude != null) {
        setState(() {
          _currentPosition = LatLng(locationData.latitude!, locationData.longitude!);
          if (_isHeadingActive && _referenceMarker == null) {
            _updateHeadingLine();
          }
        });
      }
    });
  }

  // Request location permissions and get initial location
  Future<void> _getLocationPermission() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        return;
      }
    }

    permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied ||
        permissionGranted == PermissionStatus.deniedForever) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return;
      }
    }

    var currentLocation = await _location.getLocation();
    setState(() {
      if (currentLocation.latitude != null && currentLocation.longitude != null) {
        _currentPosition = LatLng(currentLocation.latitude!, currentLocation.longitude!);
      }
      _updateTopBarText();
    });
  }

  // Start listening to compass events
  void _startCompass() {
    FlutterCompass.events?.listen((event) {
      if (event.heading != null) {
        setState(() {
          _currentBearing = event.heading!;
          _updateTopBarText();

          if (_isHeadingActive) {
            if (_headingLine == null) {
              if (_currentPosition != null) {
                _addHeadingLine();
              }
            } else {
              _updateHeadingLine();
            }
          }

          if (_isCalibrating) {
            _updateCalibrationHeadingLine();
          }
        });
      }
    });
  }

  // Update the text displayed in the top bar
  void _updateTopBarText() {
    if (_currentBearing == null) return;

    double adjustedBearing = (_currentBearing! + _compassOffset + 360) % 360;
    String compensationText = '';

    if (_isCalibrating && _initialCalibrationHeading != null) {
      // During calibration after first button press
      double potentialOffset = _angleDifference(adjustedBearing, _initialCalibrationHeading!);
      compensationText = ' (Δ: ${potentialOffset.toStringAsFixed(1)}°)';
    } else {
      compensationText = ' (Δ: ${_compassOffset.toStringAsFixed(1)}°)';
    }

    _topBarText = '${adjustedBearing.toStringAsFixed(1)}°$compensationText';
  }

  // Get the starting point for drawing lines (either reference marker or current position)
  LatLng? _getStartingPoint() {
    if (_referenceMarker != null) {
      return _referenceMarker!.position;
    } else if (_currentPosition != null) {
      return _currentPosition!;
    } else {
      return null;
    }
  }

  // Toggle the heading line on/off
  void _toggleHeading() {
    setState(() {
      _isHeadingActive = !_isHeadingActive;
      if (_isHeadingActive) {
        _addHeadingLine();
      } else {
        _removeHeadingLine();
      }
    });
  }

  // Add a heading line to the map
  void _addHeadingLine() {
    if (_currentBearing != null) {
      LatLng? startPoint = _getStartingPoint();
      if (startPoint != null) {
        double adjustedBearing =
            (_currentBearing! + _compassOffset + 360) % 360; // Apply the offset
        LatLng endPoint = _calculateEndPoint(startPoint, adjustedBearing, 20000);

        _headingLine = Polyline(
          polylineId: const PolylineId('headingLine'),
          points: [startPoint, endPoint],
          color: CupertinoColors.activeBlue,
          patterns: [PatternItem.dash(10), PatternItem.gap(10)],
          width: 5,
        );

        setState(() {
          _polylines.add(_headingLine!);
        });
      }
    }
  }

  // Remove the heading line from the map
  void _removeHeadingLine() {
    setState(() {
      _polylines.remove(_headingLine);
      _headingLine = null;
    });
  }

  // Update the heading line on the map
  void _updateHeadingLine() {
    if (_currentBearing != null) {
      LatLng? startPoint = _getStartingPoint();
      if (startPoint != null) {
        _removeHeadingLine();
        _addHeadingLine();
      }
    }
  }

  // Mark the current bearing on the map
  void _markBearing() {
    if (_currentBearing != null) {
      LatLng? startPoint = _getStartingPoint();
      if (startPoint != null) {
        double adjustedBearing = (_currentBearing! + _compassOffset + 360) % 360;
        LatLng endPoint = _calculateEndPoint(startPoint, adjustedBearing, 20000);

        Polyline polyline = Polyline(
          polylineId: PolylineId(DateTime.now().toIso8601String()),
          points: [startPoint, endPoint],
          color: CupertinoColors.activeBlue,
          width: 5,
        );

        setState(() {
          _polylines.add(polyline);
        });
      }
    }
  }

  // Calculate the end point given a start point, bearing, and distance
  LatLng _calculateEndPoint(LatLng start, double bearing, double distance) {
    const double earthRadius = 6371000; // in meters
    double bearingRad = bearing * pi / 180;
    double lat1 = start.latitude * pi / 180;
    double lon1 = start.longitude * pi / 180;

    double lat2 = asin(sin(lat1) * cos(distance / earthRadius) +
        cos(lat1) * sin(distance / earthRadius) * cos(bearingRad));
    double lon2 = lon1 +
        atan2(sin(bearingRad) * sin(distance / earthRadius) * cos(lat1),
            cos(distance / earthRadius) - sin(lat1) * sin(lat2));

    return LatLng(lat2 * 180 / pi, lon2 * 180 / pi);
  }

  // Calculate the distance based on the current zoom level
  Future<double> _calculateDistanceBasedOnZoom(LatLng firstMarkerPosition) async {
    if (_mapController == null) {
      return 500; // Default fallback distance
    }

    // Get the visible region of the map (LatLngBounds)
    LatLngBounds bounds = await _mapController!.getVisibleRegion();

    // Calculate the distances from the first marker to each edge (north, south, east, west)
    double distanceToNorth = _calculateDistance(
        firstMarkerPosition, LatLng(bounds.northeast.latitude, firstMarkerPosition.longitude));
    double distanceToSouth = _calculateDistance(
        firstMarkerPosition, LatLng(bounds.southwest.latitude, firstMarkerPosition.longitude));
    double distanceToEast = _calculateDistance(
        firstMarkerPosition, LatLng(firstMarkerPosition.latitude, bounds.northeast.longitude));
    double distanceToWest = _calculateDistance(
        firstMarkerPosition, LatLng(firstMarkerPosition.latitude, bounds.southwest.longitude));

    // Find the minimum distance
    double minDistance =
        min(distanceToNorth, min(distanceToSouth, min(distanceToEast, distanceToWest)));

    // Return 60% of the minimum distance
    return minDistance * 0.6;
  }

  // Calculate the distance between two LatLng points
  double _calculateDistance(LatLng start, LatLng end) {
    const double earthRadius = 6371000; // in meters
    double lat1 = start.latitude * pi / 180;
    double lon1 = start.longitude * pi / 180;
    double lat2 = end.latitude * pi / 180;
    double lon2 = end.longitude * pi / 180;

    double dLat = lat2 - lat1;
    double dLon = lon2 - lon1;

    double a =
        sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  // Handle long press on the map (place reference marker)
  void _onMapLongPress(LatLng latLng) {
    if (_isCalibrating) {
      // Do nothing during calibration
    } else {
      setState(() {
        if (_referenceMarker == null) {
          // Add a new reference marker
          _referenceMarker = Marker(
            markerId: const MarkerId('reference_marker'),
            position: latLng,
            draggable: true,
          );
        } else {
          _referenceMarker = _referenceMarker!.copyWith(positionParam: latLng);
        }
      });
    }
  }

  // Handle tap on the map (remove reference marker)
  void _onMapTap(LatLng latLng) {
    if (_isCalibrating) {
      // Do nothing during calibration
    } else {
      setState(() {
        _referenceMarker = null;
      });
    }
  }

  // Reset all bearings and markers on the map
  void _resetBearings() {
    setState(() {
      _polylines.clear();
      _referenceMarker = null;

      if (_isHeadingActive) {
        _addHeadingLine();
      }
    });
  }

  // Handle tab selection in the bottom navigation bar
  void _onTabSelected(int index) {
    if (_isCalibrating && index != 4) {
      // Ignore other button presses during calibration except "Calibrate"
      return;
    }
    setState(() {
      _selectedIndex = index;
      if (index == 0) {
        _markBearing();
      } else if (index == 1) {
        _toggleHeading();
      } else if (index == 2) {
        _showMapTypeSelector();
      } else if (index == 3) {
        _toggleMapOrientation();
      } else if (index == 4) {
        _toggleCalibrationMode();
      } else if (index == 5) {
        _resetBearings();
      }
    });
  }

  // Toggle map orientation between north-up and heading-up
  void _toggleMapOrientation() {
    setState(() {
      _isMapOrientedToNorth = !_isMapOrientedToNorth;
      if (_isMapOrientedToNorth) {
        _resetCameraToNorth();
      } else {
        _updateCameraToHeading();
      }
    });
  }

  // Update camera to align with current heading
  void _updateCameraToHeading() {
    if (_mapController != null && _currentPosition != null && _currentBearing != null) {
      double adjustedBearing = (_currentBearing! + _compassOffset + 360) % 360;
      _mapController!.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentPosition!,
          zoom: 15.0,
          bearing: adjustedBearing,
          tilt: 0,
        ),
      ));
    }
  }

  // Reset camera orientation to north-up
  void _resetCameraToNorth() {
    if (_mapController != null && _currentPosition != null) {
      _mapController!.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentPosition!,
          zoom: 15.0,
          bearing: 0,
          tilt: 0,
        ),
      ));
    }
  }

  // Show map type selector
  void _showMapTypeSelector() {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return CupertinoActionSheet(
          title: const Text('Select Map Type'),
          actions: [
            CupertinoActionSheetAction(
              child: const Text('Normal'),
              onPressed: () {
                setState(() {
                  _currentMapType = MapType.normal;
                });
                Navigator.pop(context);
              },
            ),
            CupertinoActionSheetAction(
              child: const Text('Satellite'),
              onPressed: () {
                setState(() {
                  _currentMapType = MapType.satellite;
                });
                Navigator.pop(context);
              },
            ),
            CupertinoActionSheetAction(
              child: const Text('Terrain'),
              onPressed: () {
                setState(() {
                  _currentMapType = MapType.terrain;
                });
                Navigator.pop(context);
              },
            ),
            CupertinoActionSheetAction(
              child: const Text('Hybrid'),
              onPressed: () {
                setState(() {
                  _currentMapType = MapType.hybrid;
                });
                Navigator.pop(context);
              },
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            child: const Text('Cancel'),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        );
      },
    );
  }

  // Toggle calibration mode
  void _toggleCalibrationMode() {
    setState(() {
      _isCalibrating = !_isCalibrating;
      if (_isCalibrating) {
        _startCalibration();
      } else {
        _endCalibration();
      }
    });
  }

  // Start the calibration process
  void _startCalibration() async {
    // Store whether heading mode was active
    _wasHeadingActive = _isHeadingActive;
    if (_isHeadingActive) {
      _isHeadingActive = false; // Deactivate heading mode
      _removeHeadingLine();
    }

    // Place the first marker at the current GPS position
    LatLng firstMarkerPosition = _currentPosition ?? const LatLng(0, 0);

    // Calculate the distance for the second marker based on the zoom level and the screen's edges
    double distance = await _calculateDistanceBasedOnZoom(firstMarkerPosition);

    // Place the second marker in the direction the phone is pointing
    if (_currentBearing != null) {
      double adjustedBearing = (_currentBearing! + _compassOffset + 360) % 360;
      LatLng secondMarkerPosition =
          _calculateEndPoint(firstMarkerPosition, adjustedBearing, distance);

      _calibrationMarker1 = Marker(
        markerId: const MarkerId('calibration_marker_1'),
        position: firstMarkerPosition,
        draggable: true,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        onDragEnd: (newPosition) => _onCalibrationMarkerDragEnd(
          const MarkerId('calibration_marker_1'),
          newPosition,
        ),
      );

      _calibrationMarker2 = Marker(
        markerId: const MarkerId('calibration_marker_2'),
        position: secondMarkerPosition,
        draggable: true,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        onDragEnd: (newPosition) => _onCalibrationMarkerDragEnd(
          const MarkerId('calibration_marker_2'),
          newPosition,
        ),
      );

      _drawCalibrationLine();

      setState(() {
        _calibrationButtonText = "Calibrate: phone aligned";
        _initialCalibrationHeading = null;
        _compassOffset = 0.0;
      });
    } else {
      // Handle the case where compass data is not available
      setState(() {
        _calibrationButtonText = "Compass data unavailable";
        _isCalibrating = false;
      });
    }
  }

  // End the calibration process
  void _endCalibration() {
    setState(() {
      _isCalibrating = false;
      _calibrationMarker1 = null;
      _calibrationMarker2 = null;
      _calibrationLine = null;
      _initialCalibrationHeading = null;
      _calibrationButtonText = "Calibrate";
      _polylines.removeWhere((polyline) => polyline.polylineId.value.startsWith('calibration'));

      if (_wasHeadingActive) {
        _isHeadingActive = true;
        _addHeadingLine();
        _wasHeadingActive = false; // Reset the flag
      }
    });
  }

  // Draw the calibration line on the map
  void _drawCalibrationLine() {
    if (_calibrationMarker1 != null && _calibrationMarker2 != null) {
      _calibrationLine = Polyline(
        polylineId: const PolylineId('calibration_line'),
        points: [_calibrationMarker1!.position, _calibrationMarker2!.position],
        color: Colors.blue,
        width: 5,
      );
      setState(() {
        _polylines.add(_calibrationLine!);
      });
    }
  }

  // Update the calibration heading line
  void _updateCalibrationHeadingLine() {
    _polylines.removeWhere((polyline) => polyline.polylineId.value == 'calibration_heading_line');

    if (_calibrationMarker1 != null && _currentBearing != null) {
      double adjustedBearing = (_currentBearing! + _compassOffset + 360) % 360;
      LatLng endPoint = _calculateEndPoint(
        _calibrationMarker1!.position,
        adjustedBearing,
        20000,
      );

      Polyline headingLine = Polyline(
        polylineId: const PolylineId('calibration_heading_line'),
        points: [_calibrationMarker1!.position, endPoint],
        color: Colors.red,
        patterns: [PatternItem.dash(10), PatternItem.gap(10)],
        width: 5,
      );

      setState(() {
        _polylines.add(headingLine);
      });
    }
  }

  // Handle drag end for calibration markers
  void _onCalibrationMarkerDragEnd(MarkerId markerId, LatLng newPosition) {
    setState(() {
      if (_calibrationMarker1 != null && markerId == _calibrationMarker1!.markerId) {
        _calibrationMarker1 = _calibrationMarker1!.copyWith(positionParam: newPosition);
      } else if (_calibrationMarker2 != null && markerId == _calibrationMarker2!.markerId) {
        _calibrationMarker2 = _calibrationMarker2!.copyWith(positionParam: newPosition);
      }
      _drawCalibrationLine();
    });
  }

  // Handle calibration button press
  void _onCalibrationButtonPressed() {
    if (_calibrationMarker1 == null || _calibrationMarker2 == null || _currentBearing == null) {
      return;
    }

    if (_initialCalibrationHeading == null) {
      _initialCalibrationHeading = (_currentBearing! + _compassOffset + 360) % 360;
      setState(() {
        _calibrationButtonText = "Calibrate: lines overlap";
        _updateTopBarText();
      });
    } else {
      double adjustedBearing = (_currentBearing! + _compassOffset + 360) % 360;
      double potentialOffset = _angleDifference(adjustedBearing, _initialCalibrationHeading!);

      setState(() {
        _compassOffset = potentialOffset;
        _updateTopBarText();
      });

      _endCalibration();
    }
  }

  // Calculate the difference between two angles
  double _angleDifference(double angle1, double angle2) {
    double difference = (angle1 - angle2 + 540) % 360 - 180;
    return difference;
  }

  // Calculate the bearing between two points
  double _calculateBearingBetweenPoints(LatLng start, LatLng end) {
    double lat1 = start.latitude * pi / 180;
    double lon1 = start.longitude * pi / 180;
    double lat2 = end.latitude * pi / 180;
    double lon2 = end.longitude * pi / 180;

    double dLon = lon2 - lon1;

    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    double brng = atan2(y, x);
    brng = brng * 180 / pi;
    brng = (brng + 360) % 360;

    return brng;
  }

  @override
  Widget build(BuildContext context) {
    // Collect all markers
    Set<Marker> markers = {};
    if (_referenceMarker != null) markers.add(_referenceMarker!);
    if (_calibrationMarker1 != null) markers.add(_calibrationMarker1!);
    if (_calibrationMarker2 != null) markers.add(_calibrationMarker2!);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          _topBarText,
          style: const TextStyle(fontSize: 16),
        ),
      ),
      child: _currentPosition == null
          ? const Center(child: CupertinoActivityIndicator())
          : Stack(
              children: [
                // The map section
                GoogleMap(
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition!,
                    zoom: 15.0,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  padding:
                      const EdgeInsets.only(bottom: 100), // Add padding for Google Maps buttons
                  polylines: _polylines,
                  mapType: _currentMapType,
                  markers: markers,
                  onLongPress: _onMapLongPress,
                  onTap: _onMapTap,
                ),
                if (_isCalibrating)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 200),
                      child: CupertinoButton.filled(
                        onPressed: _onCalibrationButtonPressed,
                        child: Text(
                          _calibrationButtonText,
                          style: const TextStyle(color: CupertinoColors.white),
                        ),
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    height: 100,
                    child: CupertinoTabBar(
                      currentIndex: _selectedIndex,
                      onTap: _onTabSelected,
                      activeColor: CupertinoColors.inactiveGray,
                      inactiveColor: CupertinoColors.inactiveGray,
                      items: [
                        const BottomNavigationBarItem(
                          icon: Icon(CupertinoIcons.arrow_up_square),
                          label: 'Mark',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(
                            _isHeadingActive
                                ? CupertinoIcons.location
                                : CupertinoIcons.location_slash,
                          ),
                          label: 'Heading',
                        ),
                        const BottomNavigationBarItem(
                          icon: Icon(CupertinoIcons.layers_alt),
                          label: 'Layers',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(
                            _isMapOrientedToNorth
                                ? CupertinoIcons.compass
                                : CupertinoIcons.location_north_fill,
                          ),
                          label: _isMapOrientedToNorth ? 'Map Align' : 'North Up',
                        ),
                        const BottomNavigationBarItem(
                          icon: Icon(CupertinoIcons.gear_alt),
                          label: 'Calibrate',
                        ),
                        const BottomNavigationBarItem(
                          icon: Icon(CupertinoIcons.clear_circled),
                          label: 'Reset',
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isTilted &&
                    _cameraController != null &&
                    _cameraController!.value.isInitialized)
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.8,
                      height: MediaQuery.of(context).size.width * 0.8,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          children: [
                            AspectRatio(
                              aspectRatio: 1.0,
                              child: CameraPreview(_cameraController!),
                            ),
                            Center(
                              child: CustomPaint(
                                painter: CrosshairPainter(),
                                size: Size.square(MediaQuery.of(context).size.width),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  // Callback when the map is created
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }
}

// Custom painter for drawing a crosshair
class CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);

    // Draw full-size crosshair
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      paint,
    );

    // Draw circle with diameter 2/3 of the square's width
    final circleRadius = size.width / 3;
    canvas.drawCircle(center, circleRadius, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
