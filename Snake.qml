import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui

// Small, theme-matched Snake overlay. Summoned via shell IPC
// (`omarchy-shell shell toggle <id> '{}'`), typically bound to a hotkey so
// it can be popped open while waiting on something else and closed again
// without losing your run.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool paused: false
  property bool gameOver: false
  property int score: 0
  property int highScore: 0

  // Workspace isolation: layer-shell surfaces aren't workspace-bound by
  // default, they float above the whole output no matter which workspace is
  // active. Remember the workspace this was opened on and auto-dismiss the
  // moment focus moves to a different one, so it doesn't follow you around.
  property int homeWorkspaceId: -1
  readonly property var focusedWorkspace: Hyprland.focusedWorkspace
  onFocusedWorkspaceChanged: {
    if (root.opened && root.homeWorkspaceId !== -1 && root.focusedWorkspace && root.focusedWorkspace.id !== root.homeWorkspaceId)
      root.dismiss()
  }

  readonly property int cols: 26
  readonly property int rows: 16
  property var snake: []
  property string direction: "right"
  property string pendingDirection: "right"
  property var food: null
  property int tickMs: 130
  readonly property int tickMinMs: 45

  // Speed controls: a 1-5 knob the player sets with +/-, independent of the
  // per-food ramp-up below. Persists across restarts and reopening the
  // overlay — it's a preference, not part of a single run.
  readonly property var speedPresets: [220, 175, 130, 95, 65]
  property int speedLevel: 3

  function changeSpeed(delta) {
    var next = Math.max(1, Math.min(root.speedPresets.length, root.speedLevel + delta))
    if (next === root.speedLevel) return
    root.speedLevel = next
    root.tickMs = Math.max(root.tickMinMs, root.speedPresets[next - 1] - root.score * 3)
    if (!root.paused && !root.gameOver) tickTimer.interval = root.tickMs
  }

  // Theme surface tokens — the [menu] surface (card chrome, already
  // alpha-composited for translucency) plus the foundational accent/urgent
  // colors for the snake and food. These are live bindings into the shell's
  // theme singleton, so switching an Omarchy theme repaints this instantly.
  property color cardColor: Color.menu.background
  property color borderColor: Color.menu.border
  property color textColor: Color.menu.text
  property color snakeColor: Color.accent
  property color snakeHeadColor: Color.foreground
  property color foodColor: Color.urgent
  property var borderSpec: Border.surfaceSpec("menu", "border", borderColor, Math.max(1, Style.space(2)))

  property int cardWidth: Style.space(500)
  property int cardHeight: Style.space(340)
  property int headerHeight: Math.max(Style.space(24), Style.font.heading + Style.spacing.controlPaddingY)

  function open(payloadJson) {
    root.opened = true
    root.homeWorkspaceId = root.focusedWorkspace ? root.focusedWorkspace.id : -1
    if (root.snake.length === 0) {
      resetGame()
    } else if (!root.gameOver && !root.paused) {
      tickTimer.start()
    }
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    canvas.requestPaint()
  }

  function close() {
    root.opened = false
    tickTimer.stop()
  }

  function dismiss() {
    root.opened = false
    tickTimer.stop()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.lennartai.snake")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function resetGame() {
    var startY = Math.floor(rows / 2)
    root.snake = [{ x: 2, y: startY }, { x: 1, y: startY }, { x: 0, y: startY }]
    root.direction = "right"
    root.pendingDirection = "right"
    root.score = 0
    root.tickMs = root.speedPresets[root.speedLevel - 1]
    root.paused = false
    root.gameOver = false
    spawnFood()
    tickTimer.interval = root.tickMs
    tickTimer.start()
  }

  function spawnFood() {
    var occupied = {}
    for (var i = 0; i < root.snake.length; i++) occupied[root.snake[i].x + "," + root.snake[i].y] = true
    var free = []
    for (var x = 0; x < cols; x++) {
      for (var y = 0; y < rows; y++) {
        if (!occupied[x + "," + y]) free.push({ x: x, y: y })
      }
    }
    root.food = free.length ? free[Math.floor(Math.random() * free.length)] : null
  }

  function turn(dir) {
    var opposite = { up: "down", down: "up", left: "right", right: "left" }
    if (dir !== opposite[root.direction]) root.pendingDirection = dir
  }

  function togglePause() {
    if (root.gameOver) return
    root.paused = !root.paused
    if (root.paused) tickTimer.stop()
    else tickTimer.start()
    canvas.requestPaint()
  }

  function hits(x, y) {
    for (var i = 0; i < root.snake.length; i++) {
      if (root.snake[i].x === x && root.snake[i].y === y) return true
    }
    return false
  }

  function step() {
    root.direction = root.pendingDirection
    var head = root.snake[0]
    var delta = { up: { x: 0, y: -1 }, down: { x: 0, y: 1 }, left: { x: -1, y: 0 }, right: { x: 1, y: 0 } }[root.direction]
    var nx = head.x + delta.x
    var ny = head.y + delta.y

    if (nx < 0 || ny < 0 || nx >= cols || ny >= rows || hits(nx, ny)) {
      root.gameOver = true
      tickTimer.stop()
      if (root.score > root.highScore) root.highScore = root.score
      canvas.requestPaint()
      return
    }

    var next = root.snake.slice()
    next.unshift({ x: nx, y: ny })

    if (root.food && nx === root.food.x && ny === root.food.y) {
      root.score += 1
      root.tickMs = Math.max(root.tickMinMs, root.speedPresets[root.speedLevel - 1] - root.score * 3)
      tickTimer.interval = root.tickMs
      spawnFood()
    } else {
      next.pop()
    }

    root.snake = next
    canvas.requestPaint()
  }

  Timer { id: tickTimer; interval: root.tickMs; repeat: true; onTriggered: root.step() }

  onCardColorChanged: canvas.requestPaint()
  onSnakeColorChanged: canvas.requestPaint()
  onSnakeHeadColorChanged: canvas.requestPaint()
  onFoodColorChanged: canvas.requestPaint()
  onTextColorChanged: canvas.requestPaint()

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-snake"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // No full-screen scrim on purpose: the point is a small overlay you can
    // play while still seeing whatever is behind it (an agent working, etc).
    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: root.cardColor
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          switch (event.key) {
          case Qt.Key_Escape:
          case Qt.Key_Q:
            root.dismiss()
            event.accepted = true
            break
          case Qt.Key_Up:
          case Qt.Key_W:
            root.turn("up")
            event.accepted = true
            break
          case Qt.Key_Down:
          case Qt.Key_S:
            root.turn("down")
            event.accepted = true
            break
          case Qt.Key_Left:
          case Qt.Key_A:
            root.turn("left")
            event.accepted = true
            break
          case Qt.Key_Right:
          case Qt.Key_D:
            root.turn("right")
            event.accepted = true
            break
          case Qt.Key_P:
            root.togglePause()
            event.accepted = true
            break
          case Qt.Key_Plus:
          case Qt.Key_Equal:
            root.changeSpeed(1)
            event.accepted = true
            break
          case Qt.Key_Minus:
            root.changeSpeed(-1)
            event.accepted = true
            break
          case Qt.Key_R:
            if (root.gameOver) root.resetGame()
            event.accepted = true
            break
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.sm

        Item {
          width: parent.width
          height: root.headerHeight

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Snake"
            color: root.textColor
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Score " + root.score + "  ·  Best " + root.highScore + "  ·  Speed " + root.speedLevel + "/" + root.speedPresets.length
            color: root.textColor
            opacity: 0.75
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }
        }

        Canvas {
          id: canvas
          width: parent.width
          height: parent.height - root.headerHeight - Style.spacing.sm - hint.height - Style.spacing.sm
          renderStrategy: Canvas.Immediate

          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            var cell = Math.floor(Math.min(width / root.cols, height / root.rows))
            var offsetX = (width - cell * root.cols) / 2
            var offsetY = (height - cell * root.rows) / 2

            for (var i = 0; i < root.snake.length; i++) {
              var seg = root.snake[i]
              ctx.fillStyle = i === 0 ? root.snakeHeadColor : root.snakeColor
              ctx.fillRect(offsetX + seg.x * cell + 1, offsetY + seg.y * cell + 1, cell - 2, cell - 2)
            }

            if (root.food) {
              ctx.fillStyle = root.foodColor
              ctx.fillRect(offsetX + root.food.x * cell + 2, offsetY + root.food.y * cell + 2, cell - 4, cell - 4)
            }

            if (root.gameOver || root.paused) {
              ctx.fillStyle = root.textColor
              ctx.globalAlpha = 0.9
              ctx.font = Style.font.title + "px " + Style.font.menuFamily
              ctx.textAlign = "center"
              ctx.textBaseline = "middle"
              ctx.fillText(root.gameOver ? "Game over — r to restart" : "Paused — p to resume", width / 2, height / 2)
              ctx.globalAlpha = 1.0
            }
          }
        }

        Text {
          id: hint
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: "wasd/arrows move · +/- speed · p pause · r restart · q/esc close"
          color: root.textColor
          opacity: 0.55
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
