import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

(:touchScreen)
class TempeFieldViewDelegate extends WatchUi.InputDelegate {
    private var _eventHandler;

    function initialize(eventHandler) {
        InputDelegate.initialize();
        _eventHandler = eventHandler.weak();
    }

    function onTap(clickEvent) {
        return _eventHandler.stillAlive()
            ? _eventHandler.get().onTap(clickEvent.getCoordinates())
            : false;
    }
}

class TempeFieldApp extends Application.AppBase {
    private var _view;

    function initialize() {
        AppBase.initialize();
        _view = new TempeFieldView();
    }

    function onStart(state as Dictionary?) as Void {
        _view.onStart();
    }

    function onStop(state as Dictionary?) as Void {
        _view.onStop();
    }

    function onSettingsChanged() as Void {
        _view.onSettingsChanged();
    }

    (:nonTouchScreen)
    function getInitialView() as Array<Views or InputDelegates>? {
        return [_view] as Array<Views or InputDelegates>;
    }

    (:touchScreen)
    function getInitialView() as Array<Views or InputDelegates>? {
        return [_view, new TempeFieldViewDelegate(_view)] as Array<Views or InputDelegates>;
    }
}