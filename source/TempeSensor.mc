using Toybox.Ant;
using Toybox.Application.Properties as Properties;

const maxReconnectRetries = 1;

class TempeSensor {
    private var _channel;
    private var _deviceNumbers = new [3];
    private var _deviceIndex = 0;
    private var _reconnectRetires = 0;

    // 0. Event count
    // 1. Low temp
    // 2. High temp
    // 3. Current temp
    // 4. Battery level
    // 5. Temperature offset
    public var data = new [6];
    public var searching = true;
    public var lastMessageTime = 0;
    public var lastDataTime = 0;

    function initialize() {
        // Load paired devices
        setupDeviceNumbers();
    }

    function open() {
        if (_channel == null) {
            _channel = new Ant.GenericChannel(method(:onMessage), new Ant.ChannelAssignment(0x00 /* CHANNEL_TYPE_RX_NOT_TX */, 1 /* NETWORK_PLUS */));
            setChannelDeviceNumber();
        }

        return _channel.open();
    }

    function close() {
        var channel = _channel;
        if (channel != null) {
            _channel = null;
            channel.release();
        }
    }

    function onMessage(message) {
        if (_channel == null) {
            //System.println("Channel is closed!");
            return;
        }

        lastMessageTime = System.getTimer();
        var payload = message.getPayload();
        var messageId = message.messageId;
        var localData = data; // To save some memory
        if (0x4E /* MSG_ID_BROADCAST_DATA */ == messageId) {
            var pageNumber = (payload[0] & 0xFF);
            if (pageNumber == 1) {
                // Were we searching?
                if (searching) {
                    searching = false;
                    // Update device number
                    setNewDeviceNumber();
                    requestBatteryStatusPage();
                }

                var eventCount = payload[2];
                if (localData[0] == eventCount) {
                    return; // Do not process the same data again
                }

                lastDataTime = System.getTimer();
                // Event count
                localData[0] = eventCount;
                // 24 Hour Low
                var temp = ((payload[4] & 0xF0) << 4) | payload[3];
                localData[1] = (temp == 0x800 ? null
                    : (temp & 0x800) == 0x800 ? -(0xFFF - temp)
                    : temp) * 0.1f;
                // 24 Hour High
                temp = (payload[5] << 4) | (payload[4] & 0x0F);
                localData[2] = (temp == 0x800 ? null
                    : (temp & 0x800) == 0x800 ? -(0xFFF - temp)
                    : temp) * 0.1f;
                // Current Temp
                temp = (payload[7] << 8) | payload[6];
                localData[3] = (temp == 0x8000 ? null
                    : (temp & 0x8000) == 0x8000 ? -(0xFFFF - temp)
                    : temp) * 0.01f;
            } else if (pageNumber == 82) {
                localData[4] = (payload[7] >> 4) & 0x07; // Battery status
            }
        } else if (0x40 /* MSG_ID_CHANNEL_RESPONSE_EVENT */ == messageId) {
            if (0x01 /* MSG_ID_RF_EVENT */ == (payload[0] & 0xFF)) {
                var eventCode = payload[1] & 0xFF;
                if (0x07 /* MSG_CODE_EVENT_CHANNEL_CLOSED */ == eventCode) {
                    // Channel closed, re-open only when the channel was not manually closed
                    if (_channel != null) {
                        if (_reconnectRetires > 0) {
                            _reconnectRetires--;
                            //System.println("Failed to connect, try to reconnect");
                        } else {
                            //System.println("Failed to connect, try connecting to the next device");
                            setNextDeviceNumber();
                        }

                        open();
                    }
                } else if (0x08 /* MSG_CODE_EVENT_RX_FAIL_GO_TO_SEARCH */ == eventCode) {
                    searching = true;
                    //System.println("MSG_CODE_EVENT_RX_FAIL_GO_TO_SEARCH");
                } else if (0x06 /* MSG_CODE_EVENT_TRANSFER_TX_FAILED */ == eventCode) {
                    //System.println("Failed to send battery status page request");
                    // The battery status page request failed to be sent, try to resend it
                    requestBatteryStatusPage();
                } else {
                    //System.println("e=" + eventCode);
                }
            }
        }
    }

    private function requestBatteryStatusPage() {
        // Get the battery page only once. For some reason the device will start sending
        // page 0 for a longer amount of time after the acknowledge is sent.
        if (data[4] != null) {
            return;
        }

        // Request battery status page
        var command = new Ant.Message();
        command.setPayload([
            0x46, // Data Page Number
            0xFF, // Reserved
            0xFF, // Reserved
            0xFF, // Descriptor Byte 1
            0xFF, // Descriptor Byte 2
            0x01, // Requested Transmission
            0x52, // Requested Page Number
            0x01  // Command Type
        ]);
        _channel.sendAcknowledge(command);
        //System.println("Requesting battery status page");
    }

    private function setNextDeviceNumber() {
        var startDeviceIndex = _deviceIndex;
        do {
            _deviceIndex = (_deviceIndex + 1) % _deviceNumbers.size();
        } while (_deviceNumbers[_deviceIndex] < 0 && startDeviceIndex != _deviceIndex);

        if (startDeviceIndex != _deviceIndex) {
            data[4] = null; // Reset battery level
        }

        //System.println("Setting device index=" + _deviceIndex);
        setChannelDeviceNumber();
    }

    private function setNewDeviceNumber() {
        _reconnectRetires = maxReconnectRetries;
        var deviceNumbers = _deviceNumbers;
        var newDeviceNumber = _channel.getDeviceConfig().deviceNumber;
        var suffix = "";
        // Find the first empty slot to insert the found device.
        for (var i = 0; i < deviceNumbers.size(); i++) {
            suffix = i == 0 ? "" : (i + 1).toString();
            if (deviceNumbers[i] == 0) {
                _deviceIndex = i;
                deviceNumbers[i] = newDeviceNumber;
                Properties.setValue("DN" + suffix, newDeviceNumber);
                break;
            } else if (deviceNumbers[i] == newDeviceNumber) {
                _deviceIndex = i;
                break;
            }
        }

        // Update temp offset
        data[5] = Properties.getValue("TO" + suffix);
        //System.println("DN=" + newDeviceNumber + " I=" + _deviceIndex + " OF=" + data[5]);
    }

    private function setChannelDeviceNumber() {
        var deviceNumber = _deviceNumbers[_deviceIndex];
        //System.println("Setting device number=" + deviceNumber);
        _channel.setDeviceConfig(new Ant.DeviceConfig({
            :deviceNumber => deviceNumber,
            :deviceType => 25,        // Environment device
            :messagePeriod => 65535,  // Channel period
            :transmissionType => 0,   // Transmission type
            :radioFrequency => 57     // Ant+ Frequency
        }));
    }

    private function setupDeviceNumbers() {
        var deviceNumbers = _deviceNumbers;
        for (var i = 0; i < deviceNumbers.size(); i++) {
            var suffix = i == 0 ? "" : (i + 1).toString();
            var deviceNumber = Properties.getValue("DN" + suffix);
            deviceNumbers[i] = deviceNumber == null ? 0 : deviceNumber;
        }
    }
}