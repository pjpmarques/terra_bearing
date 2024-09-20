
## Terra Bearing: Advanced Bearing Measurement Application

### Purpose
This application is designed for outdoor enthusiasts, surveyors, and navigation professionals who require precise compass calibration and bearing measurements. It combines GPS, magnetometer, and accelerometer data to provide accurate directional information, especially useful in areas with magnetic anomalies or when using devices with varying magnetic sensors. It also allows to  triangulate bearings between two points on the map so that users can identify features (e.g., mountains, buildings, trees) on the terrain.

Currently only iPhone is supported.

### Key Functionalities

1. Real-time compass display with offset calibration
2. GPS-based location tracking and map integration
3. Bearing measurement and visual marking on the map
4. Advanced compass calibration process
5. Toggleable map orientation (North-up vs. Heading-up)
6. Multiple map layer options (Normal, Satellite, Terrain, Hybrid)
7. Camera view integration for visual alignment during measurements
8. Tilt detection for optimal device positioning

### Notes

You will need to add a GoogleMaps API key to the ```ios/Runner/Info.plist``` file before building/running the code. Here's the relevant line:

```
	<key>GMSApiKey</key>
	<string>PLEASE_ADD_YOUR_API_KEY_HERE</string>
```

### License

[Apache 2.0](LICENSE)

