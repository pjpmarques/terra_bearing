import 'package:flutter/cupertino.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:math';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Mountain Identifier',
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
  LatLng? _fixedStartPosition; // This stores the fixed starting point for lines
  Location _location = Location();
  Set<Polyline> _polylines = Set<Polyline>();
  double? _currentBearing;
  bool _isMapOrientedToNorth = true;
  bool _isHeadingActive = false;
  int _selectedIndex = 0;
  Polyline? _headingLine;
  String _topBarText = "";
  MapType _currentMapType = MapType.normal;
  Marker? _referenceMarker; // For the reference marker

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
    if (_permissionGranted == PermissionStatus.denied) {
      _permissionGranted = await _location.requestPermission();
      if (_permissionGranted != PermissionStatus.granted) {
        return;
      }
    }

    var currentLocation = await _location.getLocation();
    setState(() {
      _currentPosition = LatLng(currentLocation.latitude!, currentLocation.longitude!);
      _topBarText = _currentBearing != null ? '${_currentBearing!.toStringAsFixed(1)}°' : '';
    });
  }

  void _startCompass() {
    FlutterCompass.events?.listen((event) {
      if (event.heading != null) {
        setState(() {
          _currentBearing = event.heading;
          _topBarText = '${_currentBearing!.toStringAsFixed(1)}°';
          if (_isHeadingActive) {
            _updateHeadingLine();
          }
        });
      }
    });
  }

  // Determine the starting point for lines (either the marker or the current location)
  LatLng _getStartingPoint() {
    return _referenceMarker != null ? _referenceMarker!.position : _currentPosition!;
  }

  // Toggle heading line visibility
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

  // Add the heading line (dashed and blue) and fix the start point
  void _addHeadingLine() {
    if (_currentBearing != null) {
      if (_fixedStartPosition == null) {
        _fixedStartPosition = _getStartingPoint(); // Fix the start point when the heading is marked
      }
      LatLng endPoint =
          _calculateEndPoint(_fixedStartPosition!, _currentBearing!, 20000); // 20 km line

      _headingLine = Polyline(
        polylineId: PolylineId('headingLine'),
        points: [_fixedStartPosition!, endPoint],
        color: CupertinoColors.activeBlue, // Blue color for heading line
        patterns: [PatternItem.dash(10), PatternItem.gap(10)], // Dashed pattern
        width: 5,
      );

      setState(() {
        _polylines.add(_headingLine!);
      });
    }
  }

  // Remove the heading line
  void _removeHeadingLine() {
    setState(() {
      _polylines.remove(_headingLine);
      _headingLine = null;
      _fixedStartPosition = null; // Reset the fixed start point
    });
  }

  // Update the heading line if it's active
  void _updateHeadingLine() {
    if (_headingLine != null) {
      _removeHeadingLine();
      _addHeadingLine();
    }
  }

  // Mark bearing and fix the start point when marking
  void _markBearing() {
    if (_currentBearing != null) {
      if (_fixedStartPosition == null) {
        _fixedStartPosition = _getStartingPoint(); // Fix the start point when bearing is marked
      }
      LatLng endPoint =
          _calculateEndPoint(_fixedStartPosition!, _currentBearing!, 20000); // 20 km line

      Polyline polyline = Polyline(
        polylineId: PolylineId(DateTime.now().toIso8601String()),
        points: [_fixedStartPosition!, endPoint],
        color: CupertinoColors.activeBlue,
        width: 5,
      );

      setState(() {
        _polylines.add(polyline);
      });
    }
  }

  // Function to calculate a point from a location using the bearing and distance
  LatLng _calculateEndPoint(LatLng start, double bearing, double distance) {
    const double earthRadius = 6371000; // in meters
    double lat1 = start.latitude * pi / 180;
    double lon1 = start.longitude * pi / 180;
    double brng = bearing * pi / 180;

    double lat2 = asin(sin(lat1) * cos(distance / earthRadius) +
        cos(lat1) * sin(distance / earthRadius) * cos(brng));
    double lon2 = lon1 +
        atan2(sin(brng) * sin(distance / earthRadius) * cos(lat1),
            cos(distance / earthRadius) - sin(lat1) * sin(lat2));

    return LatLng(lat2 * 180 / pi, lon2 * 180 / pi);
  }

  // Handle long press on map
  void _onMapLongPress(LatLng latLng) {
    setState(() {
      if (_referenceMarker == null) {
        // Add a new reference marker
        _referenceMarker = Marker(
          markerId: MarkerId('reference_marker'),
          position: latLng,
          draggable: true, // Make the marker draggable
        );
      } else {
        // If the marker already exists, update its position
        _referenceMarker = _referenceMarker!.copyWith(positionParam: latLng);
      }
    });
  }

  // Handle single press on map
  void _onMapTap(LatLng latLng) {
    setState(() {
      // Remove the reference marker on single tap
      _referenceMarker = null;
    });
  }

  // Reset all markers and bearings
  void _resetBearings() {
    setState(() {
      _polylines.clear();
      _headingLine = null;
      _referenceMarker = null; // Remove the reference marker
      _fixedStartPosition = null; // Reset fixed start point for lines

      // If Heading mode is active, redraw the heading line
      if (_isHeadingActive) {
        _addHeadingLine();
      }
    });
  }

  // Handle tab selection
  void _onTabSelected(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 0) {
        _markBearing();
      } else if (index == 1) {
        _toggleHeading();
      } else if (index == 2) {
        _showMapTypeSelector(); // Layer selector button
      } else if (index == 3) {
        _toggleMapOrientation(); // Toggle between north-up and heading-up
      } else if (index == 4) {
        _resetBearings();
      }
    });
  }

  // Handle toggling between north-up and heading-up map orientation
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

  // Update the map camera to follow the current heading (bearing)
  void _updateCameraToHeading() {
    if (mapController != null && _currentPosition != null && _currentBearing != null) {
      mapController!.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentPosition!,
          zoom: 15.0,
          bearing: _currentBearing!,
          tilt: 0,
        ),
      ));
    }
  }

  // Reset the map camera to north-up orientation
  void _resetCameraToNorth() {
    if (mapController != null && _currentPosition != null) {
      mapController!.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentPosition!,
          zoom: 15.0,
          bearing: 0, // North-up
          tilt: 0,
        ),
      ));
    }
  }

  // Show CupertinoActionSheet to select map type
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

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          _topBarText,
          style: TextStyle(fontSize: 20),
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
                  padding: EdgeInsets.only(bottom: 100), // Padding for My Location button
                  polylines: _polylines,
                  mapType: _currentMapType,
                  markers: _referenceMarker != null ? {_referenceMarker!} : {},
                  onLongPress: _onMapLongPress, // Handle long press for reference marker
                  onTap: _onMapTap, // Handle single press to remove marker
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: 100,
                    child: CupertinoTabBar(
                      currentIndex: _selectedIndex,
                      onTap: _onTabSelected,
                      activeColor: CupertinoColors.inactiveGray, // Always inactiveGray
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
