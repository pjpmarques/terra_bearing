import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:math';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Compass Calibration App',
      theme: CupertinoThemeData(
        primaryColor: CupertinoColors.inactiveGray,
      ),
      home: MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? mapController;
  LatLng? _currentPosition;
  Location _location = Location();
  Set<Polyline> _polylines = Set<Polyline>();
  double? _currentBearing;
  double _compassOffset = 0.0;
  bool _isMapOrientedToNorth = true;
  bool _isHeadingActive = true;
  bool _isCalibrating = false;
  bool _wasHeadingActive = false; // To store previous heading mode state
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

  @override
  void initState() {
    super.initState();
    _getLocationPermission();
    _startCompass();
    _listenToLocationChanges();
  }

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

  Future<void> _getLocationPermission() async {
    bool _serviceEnabled;
    PermissionStatus _permissionGranted;

    _serviceEnabled = await _location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await _location.requestService();
      if (!_serviceEnabled) {
        return;
      }
    }

    _permissionGranted = await _location.hasPermission();
    if (_permissionGranted == PermissionStatus.denied ||
        _permissionGranted == PermissionStatus.deniedForever) {
      _permissionGranted = await _location.requestPermission();
      if (_permissionGranted != PermissionStatus.granted) {
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

  LatLng? _getStartingPoint() {
    if (_referenceMarker != null) {
      return _referenceMarker!.position;
    } else if (_currentPosition != null) {
      return _currentPosition!;
    } else {
      return null;
    }
  }

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

  void _addHeadingLine() {
    if (_currentBearing != null) {
      LatLng? startPoint = _getStartingPoint();
      if (startPoint != null) {
        double adjustedBearing =
            (_currentBearing! + _compassOffset + 360) % 360; // Apply the offset
        LatLng endPoint = _calculateEndPoint(startPoint, adjustedBearing, 20000);

        _headingLine = Polyline(
          polylineId: PolylineId('headingLine'),
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

  void _removeHeadingLine() {
    setState(() {
      _polylines.remove(_headingLine);
      _headingLine = null;
    });
  }

  void _updateHeadingLine() {
    if (_currentBearing != null) {
      LatLng? startPoint = _getStartingPoint();
      if (startPoint != null) {
        _removeHeadingLine();
        _addHeadingLine();
      }
    }
  }

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

  void _onMapLongPress(LatLng latLng) {
    if (_isCalibrating) {
      // Do nothing during calibration
    } else {
      setState(() {
        if (_referenceMarker == null) {
          // Add a new reference marker
          _referenceMarker = Marker(
            markerId: MarkerId('reference_marker'),
            position: latLng,
            draggable: true,
          );
        } else {
          // If the marker already exists, update its position
          _referenceMarker = _referenceMarker!.copyWith(positionParam: latLng);
        }
      });
    }
  }

  void _onMapTap(LatLng latLng) {
    if (_isCalibrating) {
      // Do nothing during calibration
    } else {
      setState(() {
        _referenceMarker = null;
      });
    }
  }

  void _resetBearings() {
    setState(() {
      _polylines.clear();
      _referenceMarker = null;

      if (_isHeadingActive) {
        _addHeadingLine();
      }
    });
  }

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

  void _updateCameraToHeading() {
    if (mapController != null && _currentPosition != null && _currentBearing != null) {
      double adjustedBearing = (_currentBearing! + _compassOffset + 360) % 360;
      mapController!.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentPosition!,
          zoom: 15.0,
          bearing: adjustedBearing,
          tilt: 0,
        ),
      ));
    }
  }

  void _resetCameraToNorth() {
    if (mapController != null && _currentPosition != null) {
      mapController!.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentPosition!,
          zoom: 15.0,
          bearing: 0,
          tilt: 0,
        ),
      ));
    }
  }

  void _showMapTypeSelector() {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return CupertinoActionSheet(
          title: Text('Select Map Type'),
          actions: [
            CupertinoActionSheetAction(
              child: Text('Normal'),
              onPressed: () {
                setState(() {
                  _currentMapType = MapType.normal;
                });
                Navigator.pop(context);
              },
            ),
            CupertinoActionSheetAction(
              child: Text('Satellite'),
              onPressed: () {
                setState(() {
                  _currentMapType = MapType.satellite;
                });
                Navigator.pop(context);
              },
            ),
            CupertinoActionSheetAction(
              child: Text('Terrain'),
              onPressed: () {
                setState(() {
                  _currentMapType = MapType.terrain;
                });
                Navigator.pop(context);
              },
            ),
            CupertinoActionSheetAction(
              child: Text('Hybrid'),
              onPressed: () {
                setState(() {
                  _currentMapType = MapType.hybrid;
                });
                Navigator.pop(context);
              },
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            child: Text('Cancel'),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        );
      },
    );
  }

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

  void _startCalibration() {
    // Store whether heading mode was active
    _wasHeadingActive = _isHeadingActive;
    if (_isHeadingActive) {
      _isHeadingActive = false; // Deactivate heading mode
      _removeHeadingLine();
    }

    // Place the first marker at the current GPS position
    LatLng firstMarkerPosition = _currentPosition ?? LatLng(0, 0);

    // Place the second marker in the direction the phone is pointing
    if (_currentBearing != null) {
      double adjustedBearing = (_currentBearing! + _compassOffset + 360) % 360;
      LatLng secondMarkerPosition = _calculateEndPoint(firstMarkerPosition, adjustedBearing, 500);

      _calibrationMarker1 = Marker(
        markerId: MarkerId('calibration_marker_1'),
        position: firstMarkerPosition,
        draggable: true,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        onDragEnd: (newPosition) => _onCalibrationMarkerDragEnd(
          MarkerId('calibration_marker_1'),
          newPosition,
        ),
      );

      _calibrationMarker2 = Marker(
        markerId: MarkerId('calibration_marker_2'),
        position: secondMarkerPosition,
        draggable: true,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        onDragEnd: (newPosition) => _onCalibrationMarkerDragEnd(
          MarkerId('calibration_marker_2'),
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

  void _endCalibration() {
    setState(() {
      _isCalibrating = false;
      _calibrationMarker1 = null;
      _calibrationMarker2 = null;
      _calibrationLine = null;
      _initialCalibrationHeading = null;
      _calibrationButtonText = "Calibrate";
      // Remove calibration-specific polylines
      _polylines.removeWhere((polyline) => polyline.polylineId.value.startsWith('calibration'));

      // Restore heading mode if it was active before calibration
      if (_wasHeadingActive) {
        _isHeadingActive = true;
        _addHeadingLine();
        _wasHeadingActive = false; // Reset the flag
      }
    });
  }

  void _drawCalibrationLine() {
    if (_calibrationMarker1 != null && _calibrationMarker2 != null) {
      _calibrationLine = Polyline(
        polylineId: PolylineId('calibration_line'),
        points: [_calibrationMarker1!.position, _calibrationMarker2!.position],
        color: Colors.blue,
        width: 5,
      );
      setState(() {
        _polylines.add(_calibrationLine!);
      });
    }
  }

  void _updateCalibrationHeadingLine() {
    // Remove existing heading line
    _polylines.removeWhere((polyline) => polyline.polylineId.value == 'calibration_heading_line');

    if (_calibrationMarker1 != null && _currentBearing != null) {
      double adjustedBearing = (_currentBearing! + _compassOffset + 360) % 360;
      LatLng endPoint = _calculateEndPoint(
        _calibrationMarker1!.position,
        adjustedBearing,
        20000,
      );

      Polyline headingLine = Polyline(
        polylineId: PolylineId('calibration_heading_line'),
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

  void _onCalibrationButtonPressed() {
    if (_calibrationMarker1 == null || _calibrationMarker2 == null || _currentBearing == null) {
      return; // Ensure markers and compass data are available
    }

    if (_initialCalibrationHeading == null) {
      // First press: record the initial compass heading
      _initialCalibrationHeading = (_currentBearing! + _compassOffset + 360) % 360;
      setState(() {
        _calibrationButtonText = "Calibrate: lines overlap";
        _updateTopBarText();
      });
    } else {
      // Second press: calculate the compass offset
      double adjustedBearing = (_currentBearing! + _compassOffset + 360) % 360;
      double potentialOffset = _angleDifference(adjustedBearing, _initialCalibrationHeading!);

      // Update and apply the new compass offset
      setState(() {
        _compassOffset = potentialOffset;
        _updateTopBarText();
      });

      // End calibration
      _endCalibration();
    }
  }

  double _angleDifference(double angle1, double angle2) {
    double difference = (angle1 - angle2 + 540) % 360 - 180;
    return difference;
  }

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
          style: TextStyle(fontSize: 16),
        ),
      ),
      child: _currentPosition == null
          ? Center(child: CupertinoActivityIndicator())
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
                  padding: EdgeInsets.only(bottom: 100),
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
                      padding: EdgeInsets.only(bottom: 150),
                      child: CupertinoButton.filled(
                        child: Text(_calibrationButtonText),
                        onPressed: _onCalibrationButtonPressed,
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: 100,
                    child: CupertinoTabBar(
                      currentIndex: _selectedIndex,
                      onTap: _onTabSelected,
                      activeColor: CupertinoColors.inactiveGray,
                      inactiveColor: CupertinoColors.inactiveGray,
                      items: [
                        BottomNavigationBarItem(
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
                        BottomNavigationBarItem(
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
                        BottomNavigationBarItem(
                          icon: Icon(CupertinoIcons.gear_alt),
                          label: 'Calibrate',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(CupertinoIcons.clear_circled),
                          label: 'Reset',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }
}
