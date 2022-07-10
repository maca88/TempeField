using Toybox.Ant;
using Toybox.Application.Properties as Properties;

class TempeSensor {
    private var _channel;
    private var _deviceNumber;

    // 0. Event count
    // 1. Low temp
    // 2. High temp
    // 3. Current temp
    // 4. Battery level
    public var data = new [5];
    public var searching = true;
    public var lastMessageTime = 0;
    public var lastDataTime = 0;

    function open() {
        _deviceNumber = Properties.getValue("DN");
        if (_channel == null) {
            _channel = new Ant.GenericChannel(method(:onMessage), new Ant.ChannelAssignment(0x00 /* CHANNEL_TYPE_RX_NOT_TX */, 1 /* NETWORK_PLUS */));
            _channel.setDeviceConfig(new Ant.DeviceConfig({
                :deviceNumber => _deviceNumber,
                :deviceType => 25,        // Environment device
                :messagePeriod => 65535,  // Channel period
                :transmissionType => 0,   // Transmission type
                :radioFrequency => 57     // Ant+ Frequency
            }));
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
                    _deviceNumber = _channel.getDeviceConfig().deviceNumber;
                    Properties.setValue("DN", _deviceNumber);
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
                    open();
                } else if (0x08 /* MSG_CODE_EVENT_RX_FAIL_GO_TO_SEARCH */ == eventCode) {
                    searching = true;
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
}