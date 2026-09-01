import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.steveclarke.monitor-input"
  ipcTarget: "monitor-input"
  manageIpc: false

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        OpticalGlyph {
          anchors.centerIn: parent
          text: "󰝹"
          fontFamily: Style.font.family
          fontSize: Style.font.icon
          color: root.barForeground
        }
      }
    }
    onPressed: root.toggle()
  }
}
