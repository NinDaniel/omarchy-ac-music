pragma Singleton
import QtQuick

// Omarchy gives replacement bars a widget facade whose serviceFor() returns
// null, so Service.qml publishes itself here for the bar widget to fall back on.
QtObject {
  property var service: null
}
