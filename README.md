Tempe Field
=================

Tempe Field is a [data field](https://developer.garmin.com/connect-iq/connect-iq-basics/app-types/#datafields) IQ Connect application for Garmin Edge devices, that displays the data from [Tempe sensor](https://www.garmin.com/en-US/p/107335).

## Features
- Tracking average, current, min and max temperatures that are displayed in Garmin Connect
- Showing the battery level upon start
- Supports the ability to set a temperature offset that will be applied for the Tempe sensor data
- Switching between min/max 24 hour, current, activity min/max/avg temperatures and battery level by tapping on the field (only for Edge touch screen devices)

## How to use

1. [Download](https://apps.garmin.com/en-US/apps/d3889409-2a45-41b3-a4fd-b58547d1947c) the data field application from Garmin Connect Store and synchronize your Garmin Edge
2. Select the data screen where you want put the data field
3. On the chosen field select `Connect IQ` -> `Tempe Field`
4. Place Tempe sensor near Edge and the temperature should be displayed on the screen

## Unpair Tempe sensor

After the Tempe sensor is connected to Edge, its device number will be stored in the `Tempe device number` app-setting. In case you want to pair a different Tempe sensor, you need to reset `Tempe device number` app-setting by setting the value to `0`. This can be done by using either Garmin Express or Garmin Connect Mobile.

## Error codes

In case an invalid combination of settings is selected or there an issue with the ANT channel, an error will be displayed on the screen. The following errors can be displayed:
- **Error 1:** An error occurred while trying to initialize the ANT channel. Check that this data field is the only Tempe data field displayed.
- **Error 2:** The initialized ANT channel could not be opened. Check that this data field is the only Tempe data field displayed.
- **Error 3:** The field layout positions were not found.
- **Error 4:** None of the predefined battery icons fit on the screen. This error will be shown only when there is a bug in the layout. 