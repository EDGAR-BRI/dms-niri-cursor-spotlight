import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    pluginId: "cursorSpotlight"

    // Core feature states
    property bool spotlightActive: false
    property bool clicksActive: pluginData.clicksActive !== undefined ? pluginData.clicksActive : false
    property bool drawActive: false

    // Cursor tracking state (global logical coordinates across all outputs)
    property real cursorX: -1
    property real cursorY: -1
    property bool hasCursorPos: cursorX >= 0 && cursorY >= 0
    property bool mouseButtonHeld: false
    property string helperPermStatus: "OK"
    property bool permPromptShown: false

    readonly property bool anyActive: spotlightActive || clicksActive || drawActive
    readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")

    // Configurable settings via pluginData
    readonly property real spotlightRadius: Number(pluginData.spotlightRadius) || 140
    readonly property real spotlightDimOpacity: pluginData.spotlightDimOpacity !== undefined ? Number(pluginData.spotlightDimOpacity) : 0.58
    readonly property int spotlightAutoHideMs: pluginData.spotlightAutoHideMs !== undefined ? Number(pluginData.spotlightAutoHideMs) : 0
    readonly property real spotlightRingWidth: Number(pluginData.spotlightRingWidth) || 3

    readonly property real rippleSize: Number(pluginData.rippleSize) || 48
    readonly property int rippleDuration: Number(pluginData.rippleDuration) || 420
    readonly property bool showHaloWithClicks: pluginData.showHaloWithClicks !== undefined ? Boolean(pluginData.showHaloWithClicks) : true
    readonly property real haloRadius: Number(pluginData.haloRadius) || 20

    // Drawing brush settings
    property string drawColor: pluginData.drawColor || "#ff4757"
    property real drawSize: Number(pluginData.drawSize) || 5
    property bool drawLaserMode: pluginData.drawLaserMode !== undefined ? Boolean(pluginData.drawLaserMode) : false
    property int strokeRevision: 0

    readonly property var paletteColors: [
        "#ff4757", // 1: Red
        "#ffa502", // 2: Amber/Yellow
        "#2ed573", // 3: Green
        "#1e90ff", // 4: Blue
        "#ff6b81", // 5: Pink/Magenta
        "#ffffff"  // 6: White
    ]

    ListModel {
        id: ripplesModel
    }

    // Signals to broadcast draw actions to all screen canvases
    signal clearAllDrawings()
    signal undoLastDrawing()

    function savePluginSetting(key, value) {
        if (pluginService && pluginService.savePluginData) {
            pluginService.savePluginData(pluginId, key, value);
        }
    }

    function nudgeCursor() {
        Quickshell.execDetached([root.pluginDir + "/wl-nudge"]);
    }

    function requestInputPermissions() {
        const cmd = "usermod -aG input $USER && setfacl -m u:$USER:r /dev/input/event*";
        Quickshell.execDetached(["pkexec", "sh", "-c", cmd]);
    }

    function toggleSpotlight() {
        spotlightActive = !spotlightActive;
        if (spotlightActive) {
            nudgeTimer.restart();
            if (spotlightAutoHideMs > 0) {
                spotlightAutoHideTimer.interval = spotlightAutoHideMs;
                spotlightAutoHideTimer.restart();
            }
        } else {
            spotlightAutoHideTimer.stop();
        }
    }

    function pingSpotlight() {
        spotlightActive = true;
        nudgeTimer.restart();
        spotlightAutoHideTimer.interval = spotlightAutoHideMs > 0 ? spotlightAutoHideMs : 1800;
        spotlightAutoHideTimer.restart();
    }

    function toggleClicks() {
        const next = !clicksActive;
        savePluginSetting("clicksActive", next);
        if (next) {
            nudgeTimer.restart();
            if (helperPermStatus === "NEEDS_PERM" && !permPromptShown) {
                permPromptShown = true;
                ToastService.showInfo("Habilitando permisos de lectura de clicks del ratón...");
                requestInputPermissions();
            } else {
                ToastService.showInfo("Destacado de clicks activado");
            }
        } else {
            ToastService.showInfo("Destacado de clicks desactivado");
        }
    }

    function toggleDraw() {
        drawActive = !drawActive;
        if (drawActive) {
            nudgeTimer.restart();
            ToastService.showInfo("Modo Pincel activo (Esc: salir, C: limpiar, Z: deshacer, L: láser)");
        }
    }

    function spawnRipple(btn) {
        if (!hasCursorPos)
            return;
        ripplesModel.append({
            "rx": root.cursorX,
            "ry": root.cursorY,
            "btn": btn || "LEFT"
        });
    }

    Timer {
        id: nudgeTimer
        interval: 30
        repeat: false
        onTriggered: root.nudgeCursor()
    }

    Timer {
        id: spotlightAutoHideTimer
        interval: 1800
        repeat: false
        onTriggered: {
            if (root.spotlightActive && root.spotlightAutoHideMs > 0) {
                root.spotlightActive = false;
            }
        }
    }

    // IPC interface: dms ipc call cursorSpotlight <function>
    IpcHandler {
        target: "cursorSpotlight"

        function spotlightToggle(): string {
            root.toggleSpotlight();
            return root.spotlightActive ? "spotlight_enabled" : "spotlight_disabled";
        }

        function spotlightPing(): string {
            root.pingSpotlight();
            return "spotlight_ping";
        }

        function spotlightEnable(): string {
            if (!root.spotlightActive)
                root.toggleSpotlight();
            return "spotlight_enabled";
        }

        function spotlightDisable(): string {
            root.spotlightActive = false;
            return "spotlight_disabled";
        }

        function clicksToggle(): string {
            root.toggleClicks();
            return root.clicksActive ? "clicks_enabled" : "clicks_disabled";
        }

        function drawToggle(): string {
            root.toggleDraw();
            return root.drawActive ? "draw_enabled" : "draw_disabled";
        }

        function drawClear(): string {
            root.clearAllDrawings();
            return "draw_cleared";
        }

        function toggle(): string {
            root.toggleSpotlight();
            return root.spotlightActive ? "enabled" : "disabled";
        }
    }

    // Evdev helper process for global click & relative motion tracking
    Process {
        id: helperProc
        running: root.anyActive
        command: ["python3", root.pluginDir + "/cursor_helper.py"]

        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (!line)
                    return;
                const parts = line.split(" ");
                const cmd = parts[0];

                if (cmd === "STATUS") {
                    root.helperPermStatus = parts[1] || "OK";
                } else if (cmd === "DOWN") {
                    const btn = parts[1] || "LEFT";
                    root.mouseButtonHeld = true;
                    if (root.clicksActive && !root.drawActive) {
                        root.spawnRipple(btn);
                    }
                } else if (cmd === "UP") {
                    root.mouseButtonHeld = false;
                    // Re-sync exact Wayland coordinates on release
                    root.nudgeCursor();
                } else if (cmd === "MOVE" && parts.length >= 3) {
                    const dx = parseInt(parts[1]);
                    const dy = parseInt(parts[2]);
                    if (root.hasCursorPos && root.mouseButtonHeld && !isNaN(dx) && !isNaN(dy)) {
                        root.cursorX += dx;
                        root.cursorY += dy;
                    }
                }
            }
        }
    }

    // Overlay window per output screen
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property var modelData

            readonly property real localX: root.cursorX - modelData.x
            readonly property real localY: root.cursorY - modelData.y
            readonly property bool cursorOnScreen: root.hasCursorPos && localX >= 0 && localY >= 0 && localX < modelData.width && localY < modelData.height

            // Drawing state per screen
            property var strokes: []
            property var currentStroke: null

            screen: modelData
            visible: root.anyActive
            color: "transparent"

            WlrLayershell.namespace: "dms:cursor-spotlight"
            WlrLayershell.layer: WlrLayershell.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: root.drawActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Input mask:
            // - In draw mode: full screen captures pointer input for drawing.
            // - While mouseButtonHeld (dragging on underlying window): 0x0 so drags are never interrupted.
            // - In spotlight/clicks mode: full screen minus a 6x6 hole right under the cursor tip,
            //   allowing all clicks/scrolls to pass straight through while tracking any movement >=3px.
            mask: Region {
                x: 0
                y: 0
                width: root.drawActive ? win.width : (root.anyActive && !root.mouseButtonHeld ? win.width : 0)
                height: root.drawActive ? win.height : (root.anyActive && !root.mouseButtonHeld ? win.height : 0)

                Region {
                    intersection: Intersection.Subtract
                    x: (!root.drawActive && win.cursorOnScreen) ? Math.round(win.localX - 3) : -100
                    y: (!root.drawActive && win.cursorOnScreen) ? Math.round(win.localY - 3) : -100
                    width: (!root.drawActive && win.cursorOnScreen) ? 6 : 0
                    height: (!root.drawActive && win.cursorOnScreen) ? 6 : 0
                }
            }

            // Compositor Background Blur (ext-background-effect-v1) with Spotlight circular cutout!
            Region {
                id: spotlightBlurRegion
                x: 0
                y: 0
                width: root.spotlightActive ? win.width : 0
                height: root.spotlightActive ? win.height : 0

                Region {
                    intersection: Intersection.Subtract
                    x: win.cursorOnScreen ? Math.round(win.localX - root.spotlightRadius) : -1000
                    y: win.cursorOnScreen ? Math.round(win.localY - root.spotlightRadius) : -1000
                    width: win.cursorOnScreen ? Math.round(root.spotlightRadius * 2) : 0
                    height: win.cursorOnScreen ? Math.round(root.spotlightRadius * 2) : 0
                    radius: Math.round(root.spotlightRadius)
                }
            }

            BackgroundEffect.blurRegion: root.spotlightActive ? spotlightBlurRegion : null

            Connections {
                target: root
                function onClearAllDrawings() {
                    win.strokes = [];
                    win.currentStroke = null;
                    drawCanvas.requestPaint();
                }
                function onUndoLastDrawing() {
                    if (win.strokes.length > 0) {
                        win.strokes.pop();
                        drawCanvas.requestPaint();
                    }
                }
            }

            // Track pointer coordinates whenever Wayland delivers pointer enter/motion
            HoverHandler {
                id: trackerHover
                onPointChanged: {
                    if (point.position.x > 0 || point.position.y > 0) {
                        root.cursorX = win.modelData.x + point.position.x;
                        root.cursorY = win.modelData.y + point.position.y;
                    }
                }
            }

            // 1. SPOTLIGHT DIMMING + GLOW RING CANVAS
            Canvas {
                id: spotlightCanvas
                anchors.fill: parent
                visible: root.spotlightActive

                property real cx: win.localX
                property real cy: win.localY
                property bool onScreen: win.cursorOnScreen
                property real sRadius: root.spotlightRadius
                property real dimAlpha: root.spotlightDimOpacity
                property color ringColor: Theme.primary

                onCxChanged: if (visible) requestPaint()
                onCyChanged: if (visible) requestPaint()
                onOnScreenChanged: if (visible) requestPaint()
                onSRadiusChanged: if (visible) requestPaint()
                onDimAlphaChanged: if (visible) requestPaint()
                onVisibleChanged: if (visible) requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.save();
                    ctx.clearRect(0, 0, width, height);

                    // Draw dark overlay with circular spotlight hole using evenodd winding
                    ctx.beginPath();
                    ctx.rect(0, 0, width, height);
                    if (onScreen) {
                        ctx.arc(cx, cy, sRadius, 0, Math.PI * 2, true);
                    }
                    ctx.fillStyle = Qt.rgba(0, 0, 0, dimAlpha);
                    ctx.fill("evenodd");

                    // Draw glowing accent ring around the spotlight hole
                    if (onScreen) {
                        // Outer soft glow
                        ctx.beginPath();
                        ctx.arc(cx, cy, sRadius + 3, 0, Math.PI * 2);
                        ctx.strokeStyle = Qt.rgba(ringColor.r, ringColor.g, ringColor.b, 0.35);
                        ctx.lineWidth = root.spotlightRingWidth + 6;
                        ctx.stroke();

                        // Crisp inner ring
                        ctx.beginPath();
                        ctx.arc(cx, cy, sRadius, 0, Math.PI * 2);
                        ctx.strokeStyle = ringColor;
                        ctx.lineWidth = root.spotlightRingWidth;
                        ctx.stroke();

                        // Crosshair subtle center ring around pointer tip
                        ctx.beginPath();
                        ctx.arc(cx, cy, 14, 0, Math.PI * 2);
                        ctx.strokeStyle = Qt.rgba(ringColor.r, ringColor.g, ringColor.b, 0.75);
                        ctx.lineWidth = 2;
                        ctx.stroke();
                    }

                    ctx.restore();
                }
            }

            // 2. SUBTLE CURSOR HALO (when clicksActive & showHaloWithClicks)
            Rectangle {
                visible: root.clicksActive && root.showHaloWithClicks && win.cursorOnScreen && !root.drawActive
                x: win.localX - width / 2
                y: win.localY - height / 2
                width: root.haloRadius * 2
                height: root.haloRadius * 2
                radius: root.haloRadius
                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.14)
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.75)
                border.width: 2
            }

            // 3. ANIMATED CLICK RIPPLES
            Repeater {
                model: ripplesModel

                Item {
                    id: rippleItem
                    required property int index
                    required property real rx
                    required property real ry
                    required property string btn

                    readonly property real localRx: rx - win.modelData.x
                    readonly property real localRy: ry - win.modelData.y
                    readonly property color rippleColor: btn === "RIGHT" ? "#ffa502" : (btn === "MIDDLE" ? "#00d2d3" : Theme.primary)

                    property real animProgress: 0.0

                    x: localRx
                    y: localRy
                    visible: localRx >= -100 && localRy >= -100 && localRx <= win.width + 100 && localRy <= win.height + 100

                    NumberAnimation on animProgress {
                        from: 0.0
                        to: 1.0
                        duration: root.rippleDuration
                        easing.type: Easing.OutCubic
                        running: true
                        onFinished: {
                            if (rippleItem.index >= 0 && rippleItem.index < ripplesModel.count) {
                                ripplesModel.remove(rippleItem.index);
                            }
                        }
                    }

                    // Outer expanding wave
                    Rectangle {
                        readonly property real curRadius: 8 + (root.rippleSize - 8) * rippleItem.animProgress
                        x: -curRadius
                        y: -curRadius
                        width: curRadius * 2
                        height: curRadius * 2
                        radius: curRadius
                        color: Qt.rgba(rippleItem.rippleColor.r, rippleItem.rippleColor.g, rippleItem.rippleColor.b, 0.22 * (1.0 - rippleItem.animProgress))
                        border.color: Qt.rgba(rippleItem.rippleColor.r, rippleItem.rippleColor.g, rippleItem.rippleColor.b, 0.95 * (1.0 - rippleItem.animProgress))
                        border.width: Math.max(1.5, 4.0 * (1.0 - rippleItem.animProgress * 0.6))
                    }

                    // Inner secondary wave
                    Rectangle {
                        readonly property real innerProg: Math.max(0.0, (rippleItem.animProgress - 0.15) / 0.85)
                        readonly property real curRadius: 4 + (root.rippleSize * 0.65) * innerProg
                        visible: rippleItem.animProgress > 0.15
                        x: -curRadius
                        y: -curRadius
                        width: curRadius * 2
                        height: curRadius * 2
                        radius: curRadius
                        color: "transparent"
                        border.color: Qt.rgba(1, 1, 1, 0.7 * (1.0 - innerProg))
                        border.width: 2
                    }
                }
            }

            // 4. SCREEN DRAWING / BRUSH CANVAS (Modo Pincel)
            Canvas {
                id: drawCanvas
                anchors.fill: parent
                visible: root.drawActive || win.strokes.length > 0

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.save();
                    ctx.clearRect(0, 0, width, height);
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";

                    const now = Date.now();
                    const allStrokes = win.currentStroke ? win.strokes.concat([win.currentStroke]) : win.strokes;

                    for (let i = 0; i < allStrokes.length; i++) {
                        const s = allStrokes[i];
                        if (!s || !s.points || s.points.length === 0)
                            continue;

                        let alpha = 1.0;
                        if (s.laser) {
                            const age = now - s.updatedAt;
                            if (age > 1200) {
                                alpha = Math.max(0, 1.0 - (age - 1200) / 900.0);
                            }
                        }
                        if (alpha <= 0.01)
                            continue;

                        ctx.save();
                        ctx.globalAlpha = alpha;
                        ctx.strokeStyle = s.color;
                        ctx.fillStyle = s.color;
                        ctx.lineWidth = s.size;

                        if (s.laser) {
                            // Laser outer glow
                            ctx.shadowColor = s.color;
                            ctx.shadowBlur = s.size * 2.2;
                        }

                        const pts = s.points;
                        if (s.shape === "rect" && pts.length >= 2) {
                            const p0 = pts[0];
                            const p1 = pts[pts.length - 1];
                            ctx.strokeRect(p0.x, p0.y, p1.x - p0.x, p1.y - p0.y);
                        } else if (s.shape === "line" && pts.length >= 2) {
                            const p0 = pts[0];
                            const p1 = pts[pts.length - 1];
                            ctx.beginPath();
                            ctx.moveTo(p0.x, p0.y);
                            ctx.lineTo(p1.x, p1.y);
                            ctx.stroke();

                            // Draw arrowhead
                            const angle = Math.atan2(p1.y - p0.y, p1.x - p0.x);
                            const headLen = Math.max(14, s.size * 3.2);
                            ctx.beginPath();
                            ctx.moveTo(p1.x, p1.y);
                            ctx.lineTo(p1.x - headLen * Math.cos(angle - Math.PI / 6), p1.y - headLen * Math.sin(angle - Math.PI / 6));
                            ctx.lineTo(p1.x - headLen * Math.cos(angle + Math.PI / 6), p1.y - headLen * Math.sin(angle + Math.PI / 6));
                            ctx.closePath();
                            ctx.fill();
                        } else if (pts.length === 1) {
                            ctx.beginPath();
                            ctx.arc(pts[0].x, pts[0].y, s.size / 2, 0, Math.PI * 2);
                            ctx.fill();
                        } else {
                            ctx.beginPath();
                            ctx.moveTo(pts[0].x, pts[0].y);
                            for (let j = 1; j < pts.length - 1; j++) {
                                const midX = (pts[j].x + pts[j + 1].x) / 2;
                                const midY = (pts[j].y + pts[j + 1].y) / 2;
                                ctx.quadraticCurveTo(pts[j].x, pts[j].y, midX, midY);
                            }
                            const last = pts[pts.length - 1];
                            ctx.lineTo(last.x, last.y);
                            ctx.stroke();
                        }
                        ctx.restore();
                    }

                    ctx.restore();
                }
            }

            // Timer to animate laser stroke fade-out
            Timer {
                interval: 33
                repeat: true
                running: win.strokes.length > 0 && win.strokes.some(s => s.laser)
                onTriggered: {
                    const now = Date.now();
                    const filtered = win.strokes.filter(s => !s.laser || (now - s.updatedAt) < 2100);
                    if (filtered.length !== win.strokes.length) {
                        win.strokes = filtered;
                    }
                    drawCanvas.requestPaint();
                }
            }

            // Mouse and Keyboard interaction when Draw Mode is active
            MouseArea {
                id: drawMouseArea
                anchors.fill: parent
                enabled: root.drawActive
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.CrossCursor

                onPositionChanged: mouse => {
                    root.cursorX = win.modelData.x + mouse.x;
                    root.cursorY = win.modelData.y + mouse.y;
                    if (win.currentStroke) {
                        win.currentStroke.points.push({ "x": mouse.x, "y": mouse.y });
                        win.currentStroke.updatedAt = Date.now();
                        drawCanvas.requestPaint();
                    }
                }

                onPressed: mouse => {
                    root.cursorX = win.modelData.x + mouse.x;
                    root.cursorY = win.modelData.y + mouse.y;

                    if (mouse.button === Qt.RightButton) {
                        root.undoLastDrawing();
                        return;
                    }
                    if (mouse.button === Qt.MiddleButton) {
                        root.clearAllDrawings();
                        return;
                    }
                    if (mouse.button === Qt.LeftButton) {
                        if (root.clicksActive) {
                            root.spawnRipple("LEFT");
                        }
                        let shapeMode = "free";
                        if (mouse.modifiers & Qt.ShiftModifier) {
                            shapeMode = "line"; // Shift + drag = Arrow!
                        } else if (mouse.modifiers & Qt.ControlModifier) {
                            shapeMode = "rect"; // Ctrl + drag = Rectangle!
                        }
                        win.currentStroke = {
                            "points": [{ "x": mouse.x, "y": mouse.y }],
                            "color": root.drawColor,
                            "size": root.drawSize,
                            "laser": root.drawLaserMode,
                            "shape": shapeMode,
                            "updatedAt": Date.now()
                        };
                        drawCanvas.requestPaint();
                    }
                }

                onReleased: mouse => {
                    if (mouse.button === Qt.LeftButton && win.currentStroke) {
                        win.currentStroke.updatedAt = Date.now();
                        const next = win.strokes.slice();
                        next.push(win.currentStroke);
                        win.strokes = next;
                        win.currentStroke = null;
                        drawCanvas.requestPaint();
                    }
                }

                onWheel: wheel => {
                    const delta = wheel.angleDelta.y > 0 ? 1 : -1;
                    root.drawSize = Math.max(2, Math.min(32, root.drawSize + delta));
                }
            }

            // Brush size preview circle at cursor when in Draw Mode
            Rectangle {
                visible: root.drawActive && win.cursorOnScreen
                x: win.localX - width / 2
                y: win.localY - height / 2
                width: Math.max(8, root.drawSize + 4)
                height: Math.max(8, root.drawSize + 4)
                radius: width / 2
                color: "transparent"
                border.color: root.drawColor
                border.width: 2
            }

            // Keyboard shortcuts while in Draw Mode
            Item {
                focus: root.drawActive
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.drawActive = false;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_C || event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                        root.clearAllDrawings();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Z) {
                        root.undoLastDrawing();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_L) {
                        root.drawLaserMode = !root.drawLaserMode;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_B) {
                        root.toggleSpotlight();
                        event.accepted = true;
                    } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_6) {
                        const idx = event.key - Qt.Key_1;
                        if (idx >= 0 && idx < root.paletteColors.length) {
                            root.drawColor = root.paletteColors[idx];
                        }
                        event.accepted = true;
                    }
                }
            }

            // Floating HUD Toolbar for Draw Mode
            Rectangle {
                id: drawHud
                visible: root.drawActive && win.cursorOnScreen
                anchors.top: parent.top
                anchors.topMargin: 28
                anchors.horizontalCenter: parent.horizontalCenter
                width: hudRow.implicitWidth + 28
                height: 48
                radius: 24
                color: Qt.rgba(0.08, 0.09, 0.12, 0.92)
                border.color: Qt.rgba(1, 1, 1, 0.18)
                border.width: 1

                Row {
                    id: hudRow
                    anchors.centerIn: parent
                    spacing: 10

                    // Color swatches (1..6)
                    Repeater {
                        model: root.paletteColors

                        Rectangle {
                            required property string modelData
                            required property int index
                            width: 24
                            height: 24
                            radius: 12
                            anchors.verticalCenter: parent.verticalCenter
                            color: modelData
                            border.color: root.drawColor === modelData ? "#ffffff" : Qt.rgba(0, 0, 0, 0.4)
                            border.width: root.drawColor === modelData ? 3 : 1
                            scale: root.drawColor === modelData ? 1.15 : 1.0

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.drawColor = modelData
                            }
                        }
                    }

                    Rectangle {
                        width: 1
                        height: 24
                        color: Qt.rgba(1, 1, 1, 0.2)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Laser Mode Toggle (L)
                    Rectangle {
                        height: 30
                        width: laserLabel.implicitWidth + 18
                        radius: 15
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.drawLaserMode ? Qt.rgba(1, 0.28, 0.34, 0.35) : Qt.rgba(1, 1, 1, 0.08)
                        border.color: root.drawLaserMode ? "#ff4757" : "transparent"
                        border.width: 1

                        Text {
                            id: laserLabel
                            anchors.centerIn: parent
                            text: root.drawLaserMode ? "Láser (L)" : "Fijo (L)"
                            color: "#ffffff"
                            font.pixelSize: 12
                            font.bold: root.drawLaserMode
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.drawLaserMode = !root.drawLaserMode
                        }
                    }

                    // Blur Spotlight Toggle (B)
                    Rectangle {
                        height: 30
                        width: blurLabel.implicitWidth + 18
                        radius: 15
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.spotlightActive ? Qt.rgba(0.12, 0.56, 1.0, 0.35) : Qt.rgba(1, 1, 1, 0.08)
                        border.color: root.spotlightActive ? "#1e90ff" : "transparent"
                        border.width: 1

                        Text {
                            id: blurLabel
                            anchors.centerIn: parent
                            text: "Blur (B)"
                            color: "#ffffff"
                            font.pixelSize: 12
                            font.bold: root.spotlightActive
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleSpotlight()
                        }
                    }

                    // Clear Button (C)
                    Rectangle {
                        height: 30
                        width: clearLabel.implicitWidth + 18
                        radius: 15
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(1, 1, 1, 0.08)

                        Text {
                            id: clearLabel
                            anchors.centerIn: parent
                            text: "Limpiar (C)"
                            color: "#ffffff"
                            font.pixelSize: 12
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.clearAllDrawings()
                        }
                    }

                    // Exit Button (Esc)
                    Rectangle {
                        height: 30
                        width: exitLabel.implicitWidth + 18
                        radius: 15
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(1, 0.3, 0.3, 0.25)

                        Text {
                            id: exitLabel
                            anchors.centerIn: parent
                            text: "Salir (Esc)"
                            color: "#ff9999"
                            font.pixelSize: 12
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.drawActive = false
                        }
                    }
                }
            }
        }
    }
}
