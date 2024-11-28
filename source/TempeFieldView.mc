import Toybox.Activity;
import Toybox.Ant;
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
    private var _showBatteryTime = 5000;
    private var _fitFields = [];
    private var _units;
    private var _settings;
    private var _lastEventCount = -1;
    private var _currentValueIndex = 2;
    private var _batteryWidth;
    private var _batteryY;
    private var _stoppedTime;
    private var _paused = false;
    private var _trackingDelay = 0;
    private var _currentDelay = 0;
    private var _lastOnUpdateCall = 0;
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
            labels[i] = settings[1] /* Upper */ ? label.toUpper() : label;
        }

        updateTrackingDelay();
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
            _showBatteryTime = 5000; // Show battery
        }

        _paused = false;
        updateDelay();
    }

    function onTimerPause() {
        _paused = true;
        _stoppedTime = System.getTimer();
    }

    function onTimerStop() {
        if (!_paused) {
            _stoppedTime = System.getTimer();
        }
    }

    function onTimerResume() {
        _paused = false;
        updateDelay();
    }

    // Called from TempeFieldApp.onSettingsChanged()
    function onSettingsChanged() {
        updateTrackingDelay();
        // Reset ANT channel in case the device number was changed
        onStop();
        onStart();
    }

    function compute(info as Activity.Info) as Numeric or Duration or String or Null {
        var sensorData = _sensor.data;
        var timerState = info.timerState;
        if (timerState == 3 /* TIMER_STATE_ON */ && _currentDelay > 0) {
            _currentDelay--;
        }

        if (sensorData[0] != null && sensorData[0] != _lastEventCount) {
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
                var tempOffset = sensorData[5];
                values[i] += tempOffset == null ? 0f : tempOffset;
            }

            if (timerState != null && timerState != 0 /* TIMER_STATE_OFF */) {
                // Current temperature is always updated when the recording is active
                var currentTemp = values[2];
                _fitFields[0].setData(currentTemp);
                //System.println("Updating current temp");

                // Update max/min/avg only when timer state is on
                if (timerState != 3 /* TIMER_STATE_ON */) {
                    return null;
                }

                // Skip updating if the delay is set
                if (_currentDelay > 0) {
                    //System.println("Skip, delay in progress=" + _currentDelay);
                    return null;
                }

                //System.println("Updating min/max/avg temps");

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
                for (var i = 1; i < 4; i++) {
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
        var timer = System.getTimer();
        var lastMessageTime = sensor.lastMessageTime;
        var lastOnUpdateCall = _lastOnUpdateCall;
        _lastOnUpdateCall = timer;
        // In case the device goes to sleep for a longer period of time the channel will be closed by the system
        // and TempeSensor.onMessage won't be called anymore. In such case release the current channel and open
        // a new one. To detect a sleep we check whether the last message was received more than the value of
        // the option "searchTimeoutLowPriority" ago, which in our case is set to 15 seconds.
        if (lastMessageTime > 0 && timer - lastMessageTime > 20000) {
            onSettingsChanged();
        }

        var bgColor = getBackgroundColor();
        var fgColor = Graphics.COLOR_BLACK;
        if (bgColor == Graphics.COLOR_BLACK) {
            fgColor = Graphics.COLOR_WHITE;
        }

        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.clear();

        if (_positions == null) {
            preCalculate(dc);
        }

        if (_errorCode) {
            dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, 0, "Error: " + _errorCode, 1 /* TEXT_JUSTIFY_CENTER */ | 4 /* TEXT_JUSTIFY_VCENTER */);
            return;
        }

        var pos = _positions;
        var settings = _settings;
        var batteryStatus = _sensor.data[4];
        var currentValueIndex = (_showBatteryTime > 0 && batteryStatus != null) ? 6 : _currentValueIndex;

        // Draw label
        if (pos[0] != null && settings[3] /* Write label after value */ == false) {
            dc.drawText(pos[0], pos[1], pos[2], _labels[currentValueIndex], pos[3]);
            // Debug
            //var dim = dc.getTextDimensions(_labels[currentValueIndex], pos[2]);
            //var fontX = pos[0] - (dim[0] / 2);
            //dc.drawRectangle(fontX, pos[1], dim[0], dim[1]);
            //dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_BLACK);
            //var py = pos[1] + dim[1] - dc.getFontDescent(pos[2]);
            //dc.drawLine(fontX, py, fontX + dim[0], py);
        }

        // Draw battery
        if (currentValueIndex == 6) {
            if (batteryStatus == null) {
                batteryStatus = 6; // Draw empty battery
            }

            var batteryWidth = _batteryWidth; // 52, 42, 37
            var batteryHeight = batteryWidth / 2;
            var barWidth = batteryWidth / 5 - 2;
            var barHeight = batteryHeight - 7;
            var topHeight = batteryHeight - batteryHeight / 3;
            var x = pos[8] == 0 ? pos[5] - batteryWidth - 4 : pos[5] - batteryWidth / 2 - (topHeight / 2) + 4;
            var y = _batteryY; // (pos[6] < 0 ? 0 : pos[6]) + batteryHeight / 2;
            var color = batteryStatus == 5 /* BATT_STATUS_CRITICAL */ ? 0xFF0000 /* COLOR_RED */
                : batteryStatus > 2 /* BATT_STATUS_GOOD */ ? 0xFF5500 /* COLOR_ORANGE */
                : 0x00AA00; /* COLOR_DK_GREEN */
            //System.println("h=" + height + " bw=" + barWidth + " bh" + barHeight + " th=" + topHeight);
            dc.setPenWidth(2);
            dc.drawRectangle(x, y, batteryWidth + 3, batteryHeight);
            dc.drawRectangle(x + batteryWidth + 2, y + batteryHeight / 6, batteryHeight / 4, topHeight);
            if (!settings[0] /* Monochrome */) {
                dc.setColor(color, bgColor);
            }

            for (var i = 0; i < (6 - batteryStatus); i++) {
                dc.fillRectangle(x + 3 + (barWidth + 2) * i, y + 3, barWidth, barHeight);
            }

            var diff = timer - lastOnUpdateCall;
            _showBatteryTime -= (diff > 2000 ? 0 : diff);
            dc.setColor(fgColor, bgColor);
        } else {
            // Draw value
            var value = _values[currentValueIndex];
            value = value != null && (timer - sensor.lastDataTime) < 70000
                ? value.format("%.1f")
                : settings[2]; // Default value
            dc.drawText(pos[5], pos[6], pos[7], value, pos[8]);

            // Debug
            //var dim = dc.getTextDimensions(value, pos[7]);
            //var fontX = pos[5] - (dim[0] / 2);
            //dc.drawRectangle(fontX, pos[6], dim[0], dim[1]);
        }

        if (pos[0] != null && settings[3] /* Write label after value */ == true) {
            dc.drawText(pos[0], pos[1], pos[2], _labels[currentValueIndex], pos[3]);
            // Debug
            //var dim = dc.getTextDimensions(_labels[currentValueIndex], pos[2]);
            //var fontX = pos[0] - (dim[0] / 2);
            //dc.drawRectangle(fontX, pos[1], dim[0], dim[1]);
            //dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_BLACK);
            //var py = pos[1] + dim[1] - dc.getFontDescent(pos[2]);
            //dc.drawLine(fontX, py, fontX + dim[0], py);
        }
    }

    private function preCalculate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var flags = getObscurityFlags();
        var layouts = WatchUi.loadResource(Rez.JsonData.Layouts);
        var totalLayouts = layouts.size() / 3;
        var settings = _settings;
        _batteryWidth = null;
        for (var i = 0; i < totalLayouts; i++) {
            var index = i * 3;
            var layoutWidth = layouts[index];
            var layoutHeight = layouts[index + 1];
            var layoutFlags = layouts[index + 2];
            if ((layoutWidth - width).abs() <= 3 && (layoutHeight - height).abs() <= 3 && layoutFlags == flags) {
                layouts = null; // Free resources
                var positions = WatchUi.loadResource(Rez.JsonData[layoutResources[i]]);
                positions[6] -= Graphics.getFontAscent(positions[7]);
                var startY = 0;
                if (positions[1]) {
                    positions[1] -= Graphics.getFontAscent(positions[2]);
                    startY = positions[1] + dc.getFontHeight(positions[2]);
                    if (settings[3] /* Write label after value */ == false) {
                        startY -= dc.getFontDescent(positions[2]);
                    }
                }

                //System.println("found=" + i + " lh=" + layoutHeight + " lw=" + layoutWidth + " h=" + height + " w=" + width + " f=" + flags + " pos=" + positions);

                // Calculate battery width
                var availHeight = height - startY;
                var batteryWidths = [72, 62, 52, 42, 37];
                for (var j = 0; j < batteryWidths.size(); j++) {
                    var batteryWidth = batteryWidths[j];
                    if (settings[4] /* Max battery width */ >= batteryWidth && availHeight - ((batteryWidth / 2) + 4 /* borders*/) > 0) {
                        _batteryWidth = batteryWidth;
                        break;
                    }
                }

                if (_batteryWidth == null) {
                    _errorCode = 4;
                    return;
                }

                // Store the pre-calculated values
                _positions = positions;
                var diffY = availHeight - (_batteryWidth / 2) /* height */;
                _batteryY = startY + (diffY / 2) + 1 /* borders */;
                if (flags == 9 /* bottom left */ || flags == 12 /* bottom right */) {
                    _batteryY -= (diffY / 4);
                }

                //System.println("availH=" + availHeight + " batW=" + _batteryWidth + " batY=" + _batteryY);
                return;
            }
        }

        _errorCode = 3;
    }

    private function updateDelay() {
        if (_trackingDelay == 0) {
            return; // By default do not add any delay
        }

        var time = _stoppedTime != null ? (System.getTimer() - _stoppedTime) / 1000 : _trackingDelay;
        _currentDelay += time > _trackingDelay ? _trackingDelay : time;
        if (_currentDelay > _trackingDelay) {
            _currentDelay = _trackingDelay;
        }

        //System.println("diff=" + (time) + " CD[s]=" + _currentDelay);
    }

    private function updateTrackingDelay() {
        var trackingDelay = Properties.getValue("TD");
        if (trackingDelay == null) {
            trackingDelay = 0;
        } else {
            trackingDelay = trackingDelay * 60;
        }

        _trackingDelay = trackingDelay;
    }
}