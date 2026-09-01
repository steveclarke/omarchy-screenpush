// Positive control for tools/lint-qml. Deliberately broken: KeyboardPanel's
// required `anchorItem` and `bar` are unset, and a Repeater child reproduces
// the qmllint 6.11.2 blind spot that hid this exact defect in Setup.qml.
// The gate lints this on every run and fails if the finding does NOT appear -
// a checker that silently stops checking is worse than no checker.
import QtQuick
import qs.Ui

Item {
  id: root
  KeyboardPanel {
    owner: root
    open: true
    Repeater { model: 3; delegate: Item {} }
  }
}
