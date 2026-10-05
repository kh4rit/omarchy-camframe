import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Camera framing for the "Studio Display Framed" virtual camera, modelled on
// macOS's camera framing control: a live view of the whole camera with the
// framed area outlined. Drag the frame to move it, scroll or use the slider to
// zoom, double-click to reset. The `camframe` service bundled with this plugin
// does the work; this panel only reads its state/preview files and calls
// `camframe set`.
Panel {
  id: root
  moduleName: "kh4rit.camframe"
  ipcTarget: "kh4rit.camframe"

  readonly property string camframe: decodeURIComponent(Qt.resolvedUrl("camframe").toString().replace(/^file:\/\//, ""))
  readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR") + "/camframe"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/camframe"
  readonly property bool mirrored: setting("mirrorPreview", true)
  readonly property real zoomMin: 1.0
  readonly property real zoomMax: 3.0

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool live: false
  property bool serviceUp: false
  property string label: "Framed Camera"
  property real zoom: 1.0
  property real cx: 0.5
  property real cy: 0.5
  property bool dragging: false
  property bool dirty: false
  property int frame: 0

  // Fraction of the camera image covered by the 16:9 frame at zoom 1.
  readonly property real camW: preview.sourceSize.width > 0 ? preview.sourceSize.width : 16
  readonly property real camH: preview.sourceSize.height > 0 ? preview.sourceSize.height : 9
  readonly property real baseW: Math.min(1, (camH * 16 / 9) / camW)
  readonly property real baseH: Math.min(1, (camW * 9 / 16) / camH)
  readonly property real frameW: baseW / zoom
  readonly property real frameH: baseH / zoom

  function clampCenter() {
    cx = Math.max(frameW / 2, Math.min(1 - frameW / 2, cx))
    cy = Math.max(frameH / 2, Math.min(1 - frameH / 2, cy))
  }

  function setFraming(z, x, y) {
    zoom = Math.max(zoomMin, Math.min(zoomMax, z))
    cx = x
    cy = y
    clampCenter()
    dirty = true
  }

  function reset() { setFraming(1, 0.5, 0.5) }

  // Camera x (0..1) <-> x in the preview, which may be mirrored like a self-view.
  function viewX(nx) { return mirrored ? 1 - nx : nx }

  function push() {
    if (!dirty) return
    dirty = false
    Quickshell.execDetached([camframe, "set", zoom.toFixed(3), cx.toFixed(4), cy.toFixed(4)])
  }

  function applyState(text) {
    if (dragging || dirty) return
    try {
      var s = JSON.parse(text)
      zoom = Number(s.zoom) || 1
      cx = s.cx === undefined ? 0.5 : Number(s.cx)
      cy = s.cy === undefined ? 0.5 : Number(s.cy)
    } catch (e) {}
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    path: root.stateDir + "/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyState(text())
  }

  FileView {
    path: root.runDir + "/status"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var st = JSON.parse(text())
        root.serviceUp = true
        root.live = st.state === "live"
        if (st.label) root.label = st.label
      } catch (e) {
        root.serviceUp = false
        root.live = false
      }
    }
    onLoadFailed: { root.serviceUp = false; root.live = false }
  }

  // Keep the camera open for the preview while the panel is showing; the
  // service closes it a few seconds after the last touch.
  Timer {
    interval: 1000
    repeat: true
    triggeredOnStart: true
    running: root.opened && root.serviceUp
    onTriggered: Quickshell.execDetached([root.camframe, "preview"])
  }

  Timer {
    interval: 125
    repeat: true
    running: root.opened && root.live
    onTriggered: root.frame++
  }

  // Throttle `camframe set` calls while dragging or scrolling.
  Timer {
    interval: 60
    repeat: true
    running: root.dirty
    onTriggered: root.push()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰄀"
    active: root.live
    tooltipText: root.live ? "Camera in use · framing" : "Camera framing"
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.reset()
      else root.toggle()
    }
  }

  PopupCard {
    id: card
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: card.fittedContentWidth(Style.space(440))
    contentHeight: card.fittedContentHeight(content.implicitHeight)

    Column {
      id: content
      width: parent.width
      spacing: Style.space(10)

      Item {
        width: parent.width
        height: title.implicitHeight

        Text {
          id: title
          text: "Camera framing"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: title.verticalCenter
          text: !root.serviceUp ? "Service not running" : root.live ? "● Live" : "Starting camera…"
          color: root.live ? root.accent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Item {
        id: view
        width: parent.width
        height: Math.round(width * root.camH / root.camW)
        clip: true

        Rectangle {
          anchors.fill: parent
          color: "#202020"
        }

        Image {
          id: preview
          anchors.fill: parent
          cache: false
          asynchronous: false
          fillMode: Image.Stretch
          mirror: root.mirrored   // like a call app's self-view; frame and mouse use viewX()
          source: root.opened ? "file://" + root.runDir + "/preview.jpg?" + root.frame : ""
        }

        // Shade everything outside the frame.
        Rectangle { color: "#99000000"; x: 0; y: 0; width: parent.width; height: frameRect.y }
        Rectangle { color: "#99000000"; x: 0; y: frameRect.y + frameRect.height; width: parent.width; height: parent.height - y }
        Rectangle { color: "#99000000"; x: 0; y: frameRect.y; width: frameRect.x; height: frameRect.height }
        Rectangle { color: "#99000000"; x: frameRect.x + frameRect.width; y: frameRect.y; width: parent.width - x; height: frameRect.height }

        Rectangle {
          id: frameRect
          width: root.frameW * view.width
          height: root.frameH * view.height
          x: (root.viewX(root.cx) - root.frameW / 2) * view.width
          y: (root.cy - root.frameH / 2) * view.height
          color: "transparent"
          border.color: root.accent
          border.width: Math.max(2, Style.space(2))
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
          property real grabDx: 0
          property real grabDy: 0

          onPressed: function(m) {
            var px = root.viewX(m.x / view.width), py = m.y / view.height
            var inside = Math.abs(px - root.cx) <= root.frameW / 2 && Math.abs(py - root.cy) <= root.frameH / 2
            // Grab the frame where clicked, or jump it to the click point.
            grabDx = inside ? root.cx - px : 0
            grabDy = inside ? root.cy - py : 0
            root.dragging = true
            root.setFraming(root.zoom, px + grabDx, py + grabDy)
          }
          onPositionChanged: function(m) {
            if (!root.dragging) return
            root.setFraming(root.zoom, root.viewX(m.x / view.width) + grabDx, m.y / view.height + grabDy)
          }
          onReleased: { root.dragging = false; root.push() }
          onDoubleClicked: root.reset()
          onWheel: function(w) {
            var f = w.angleDelta.y > 0 ? 1.08 : 1 / 1.08
            root.setFraming(root.zoom * f, root.cx, root.cy)
          }
        }
      }

      Item {
        width: parent.width
        height: Style.space(28)

        Text {
          id: zoomLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(44)
          text: root.zoom.toFixed(1) + "×"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        PanelSlider {
          bar: root.bar
          anchors.left: zoomLabel.right
          anchors.right: resetButton.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          height: parent.height
          minimum: root.zoomMin
          maximum: root.zoomMax
          step: 0.05
          value: root.zoom
          onMoved: function(v) { root.setFraming(v, root.cx, root.cy) }
          onReleased: function(v) { root.push() }
        }

        PanelActionButton {
          id: resetButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰑓"
          tooltipText: "Reset framing"
          foreground: root.foreground
          onClicked: root.reset()
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: root.serviceUp
          ? "Drag to move · scroll to zoom · double-click to reset. Select “" + root.label + "” as the camera in your call app."
          : "Run “camframe setup” in a terminal (see the plugin README), then reopen this panel."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
