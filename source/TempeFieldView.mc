import Toybox.Activity;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;
using Toybox.Application.Properties as Properties;

class TempeFieldView extends WatchUi.DataField {

    private var _positions;
    private var _errorCode;
    private var _labels;
    private var _sensor;
    private var _tempFitField;
    private var _showBatteryTime = 5;
    private var _fitFields = [];
    private var _units;
    private var _settings;
    private var _lastEventCount = -1;
    private var _currentValueIndex = 2;
    private var _tempOffset = 0f;
    // 0. Min 24H temp
    // 1. Max 24H temp
    // 2. Current temp
    // 3. Min activity temp
    // 4. Max activity temp
    // 5. Avg activity temp
    // 6. Avg temp sum
    // 7. Avg count
    private var _values = new [8];

    function initialize() {
        DataField.initialize();
        var settings = WatchUi.loadResource(Rez.JsonData.Settings);
        var labels = [
            :Min24HTemperature,
            :Max24HTemperature,
            :Temperature,
            :MinTemperature,
            :MaxTemperature,
            :AverageTemperature,
            :TempeBattery
        ];
        var i;
        for (i = 0; i < labels.size(); i++) {
            var label = WatchUi.loadResource(Rez.Strings[labels[i]]);
            labels[i] = settings[2] /* Upper */ ? label.toUpper() : label;
        }

        _labels = labels;
        _settings = settings;
        _units = System.getDeviceSettings().temperatureUnits;
        for (i = 0; i < 4; i++) {
            _fitFields.add(createField(
                "tempe" + i,
                _units == 0 /* UNIT_METRIC */ ? i : i + 4,
                8 /* DATA_TYPE_FLOAT */,
                {
                    :mesgType=> i == 0 /* Temperature */ ? 20 /* Fit.MESG_TYPE_RECORD */ : 18 /* MESG_TYPE_SESSION */
                }));
        }
    }

    // Called from TempeFieldApp.onStart()
    function onStart() {
        // Update app settings
        _tempOffset = Properties.getValue("TO");
        // Initialize ANT channel
        var errorCode = null;
        try {
            if (_sensor == null) {
                _sensor = new TempeSensor();
            }

            if (!_sensor.open()) {
                errorCode = 2;
            }
        } catch (e instanceof Ant.UnableToAcquireChannelException) {
            errorCode = 1;
        }

        _errorCode = errorCode;
    }

    // Called from TempeFieldApp.onStop()
    function onStop() {
        if (_sensor != null) {
            _sensor.close();
            _sensor = null;
        }
    }

    function onTimerStart() {
        if (_sensor.data[4] == 5 /* CRITICAL */) {
            _showBatteryTime = 5; // Show battery
        }
    }

    // Called from TempeFieldApp.onSettingsChanged()
    function onSettingsChanged() {
        // Reset ANT channel in case the device number was changed
        onStop();
        onStart();
    }

    function compute(info as Activity.Info) as Numeric or Duration or String or Null {
        var sensorData = _sensor.data;
        if (sensorData[0] != _lastEventCount && sensorData[0] != null) {
            _lastEventCount = sensorData[0];
            var values = _values;
            for (var i = 0; i < 3; i++) {
                // Copy values from the sensor
                values[i] = sensorData[i + 1]; // 0 -> Low 24H temp, 1 -> Max 24H temp, 2 -> Current temp

                // Convert to fahrenheit if needed
                if (_units == 1 /* UNIT_STATUTE */) {
                    values[i] = values[i] * 1.8f + 32f; // Convert to fahrenheit
                }

                // Apply offset
                values[i] += _tempOffset;
            }

            if (info.timerState != null && info.timerState != 0) {
                var currentTemp = values[2];
                // Update min activity temp
                if (values[3] == null || values[3] > currentTemp) {
                    values[3] = currentTemp;
                }

                // Update max activity temp
                if (values[4] == null || values[4] < currentTemp) {
                    values[4] = currentTemp;
                }

                // Update avg temp data
                if (values[5] == null) {
                    values[6] = currentTemp; // Initialize avg temp sum
                    values[7] = 1; // Initialize avg count
                } else {
                    values[6] += currentTemp; // Update avg temp sum
                    values[7]++;  // Increase avg count
                }

                // Calculate avg temp
                values[5] = values[6] / values[7].toFloat(); // Avg temp

                // Record fit values
                for (var i = 0; i < 4; i++) {
                    _fitFields[i].setData(values[i + 2]);
                }
            }
        }

        return null;
    }

    function onLayout(dc) {
        // Due to getObsurityFlags returning incorrect results here, we have to postpone the calculation to onUpdate method
        _positions = null; // Force to pre-calculate again
    }

    (:touchScreen)
    function onTap(location) {
        _currentValueIndex = (_currentValueIndex + 1) % 7;
        return true;
    }

    function onUpdate(dc) {
        var sensor = _sensor;
        var lastMessageTime = sensor.lastMessageTime;
        var timer = System.getTimer();
        // In case the device goes to sleep for a longer period of time the channel will be closed by the system
        // and TempeSensor.onMessage won't be called anymore. In such case release the current channel and open
        // a new one. To detect a sleep we check whether the last message was received more than the value of
        // the option "searchTimeoutLowPriority" ago, which in our case is set to 15 seconds.
        if (lastMessageTime > 0 && timer - lastMessageTime > 20000) {
            onSettingsChanged();
        }

        var bgColor = getBackgroundColor();
        var fgColor = 0x000000; /* COLOR_BLACK */
        if (bgColor == 0x000000 /* COLOR_BLACK */) {
            fgColor = 0xFFFFFF; /* COLOR_WHITE */
        }

        dc.setColor(fgColor, bgColor);
        dc.clear();
        if (_errorCode) {
            dc.drawText(width / 2, height / 2, 0, text, 1 /* TEXT_JUSTIFY_CENTER */ | 4 /* TEXT_JUSTIFY_VCENTER */);
            return;
        }

        if (_positions == null) {
            preCalculate(dc);
        }

        var pos = _positions;
        var settings = _settings;
        var batteryStatus = _sensor.data[4];
        var currentValueIndex = (_showBatteryTime > 0 && batteryStatus != null) ? 6 : _currentValueIndex;

        // Draw label
        if (pos[0] != null) {
            dc.drawText(pos[0], pos[1], pos[2], _labels[currentValueIndex], pos[3]);
        }

        // Draw battery
        if (currentValueIndex == 6) {
            if (batteryStatus == null) {
                batteryStatus = 6; // Draw empty battery
            }

            var batteryWidth = settings[0]; // 52, 42, 37
            var batteryHeight = batteryWidth / 2;
            var barWidth = batteryWidth / 5 - 2;
            var barHeight = batteryHeight - 7;
            var topHeight = batteryHeight - batteryHeight / 3;
            var x = pos[8] == 0 ? pos[5] - batteryWidth - 4 : pos[5] - batteryWidth / 2 - (topHeight / 2) + 4;
            var y = pos[6] + batteryHeight / 2;
            var color = batteryStatus == 5 /* BATT_STATUS_CRITICAL */ ? 0xFF0000 /* COLOR_RED */
                : batteryStatus > 2 /* BATT_STATUS_GOOD */ ? 0xFF5500 /* COLOR_ORANGE */
                : 0x00AA00; /* COLOR_DK_GREEN */
            //System.println("h=" + height + " bw=" + barWidth + " bh" + barHeight + " th=" + topHeight);
            dc.setPenWidth(2);
            dc.drawRectangle(x, y, batteryWidth + 3, batteryHeight);
            dc.drawRectangle(x + batteryWidth + 2, y + batteryHeight / 6, batteryHeight / 4, topHeight);
            if (!settings[1] /* Monochrome */) {
                dc.setColor(color, bgColor);
            }

            for (var i = 0; i < (6 - batteryStatus); i++) {
                dc.fillRectangle(x + 3 + (barWidth + 2) * i, y + 3, barWidth, barHeight);
            }

            _showBatteryTime--;
            dc.setColor(fgColor, bgColor);
        } else {
            // Draw value
            var value = _values[currentValueIndex];
            value = value != null && (timer - sensor.lastDataTime) < 70000
                ? value.format("%.1f")
                : settings[3];
            dc.drawText(pos[5], pos[6], pos[7], value, pos[8]);
        }
    }

    private function preCalculate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var flags = getObscurityFlags();
        var layouts = WatchUi.loadResource(Rez.JsonData.Layouts);
        var totalLayouts = layouts.size() / 3;
        for (var i = 0; i < totalLayouts; i++) {
            var index = i * 3;
            var layoutWidth = layouts[index];
            var layoutHeight = layouts[index + 1];
            var layoutFlags = layouts[index + 2];
            if ((layoutWidth - width).abs() <= 2 && (layoutHeight - height).abs() <= 2 && layoutFlags == flags) {
                layouts = null; // Free resources
                var positions = WatchUi.loadResource(Rez.JsonData[layoutResources[i]]);
                positions[6] -= Graphics.getFontAscent(positions[7]);
                if (positions[1]) {
                    positions[1] -= Graphics.getFontAscent(positions[2]);
                }

                _positions = positions;
                //System.println("found=" + i + " lh=" + layoutHeight + " h=" + height + " pos=" + _positions);
                return;
            }
        }

        _errorCode = 3;
    }
}