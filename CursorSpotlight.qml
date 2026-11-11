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

    function boolVal(val, fallback) {
        if (val === undefined || val === null)
            return fallback;
        if (val === false || val === "false" || val === 0 || val === "0")
            return false;
        return Boolean(val);
    }

    // Core feature states
    property bool spotlightActive: false
    property bool clicksActive: boolVal(pluginData.clicksActive, false)
    property bool drawActive: false

    // Cursor tracking state (global logical coordinates across all outputs)
    property real cursorX: -1
    property real cursorY: -1
    property bool hasCursorPos: cursorX >= 0 && cursorY >= 0
    property bool mouseButtonHeld: false
    property string helperPermStatus: "UNKNOWN"
    property bool permPromptShown: false

    // Click pulse animation state for the cursor halo itself
    property real haloScale: 1.0
    property real clickFlash: 0.0
    property color activeClickColor: leftColorResolved

    readonly property bool anyActive: spotlightActive || clicksActive || drawActive
    readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")

    // Spotlight settings
    readonly property real spotlightRadius: Number(pluginData.spotlightRadius) || 140
    readonly property real spotlightDimPercent: pluginData.spotlightDimPercent !== undefined ? Number(pluginData.spotlightDimPercent) : 58
    readonly property real spotlightDimOpacity: Math.max(0.0, Math.min(0.95, spotlightDimPercent / 100.0))
    readonly property int spotlightAutoHideSec: pluginData.spotlightAutoHideSec !== undefined ? Number(pluginData.spotlightAutoHideSec) : 0
    readonly property int spotlightAutoHideMs: spotlightAutoHideSec * 1000
    readonly property real spotlightRingWidth: pluginData.spotlightRingWidth !== undefined ? Number(pluginData.spotlightRingWidth) : 3
    readonly property color spotlightColorResolved: pluginData.spotlightCustomColor ? Qt.color(pluginData.spotlightCustomColor) : Theme.primary

    // Click & Halo settings
    readonly property bool showHaloWithClicks: boolVal(pluginData.showHaloWithClicks, true)
    readonly property real haloRadius: Number(pluginData.haloRadius) || 20
    readonly property real haloGrowPercent: pluginData.haloGrowPercent !== undefined ? Number(pluginData.haloGrowPercent) : 175
    readonly property real haloTargetScale: Math.max(1.0, haloGrowPercent / 100.0)
    readonly property bool showShockwave: boolVal(pluginData.showShockwave, true)
    readonly property bool showRadialBurst: boolVal(pluginData.showRadialBurst, true)
    readonly property real rippleSize: Number(pluginData.rippleSize) || 58
    readonly property int rippleDuration: Number(pluginData.rippleDuration) || 460

    // Custom colors per mouse button
    readonly property color leftColorResolved: pluginData.leftClickColor ? Qt.color(pluginData.leftClickColor) : Theme.primary
    readonly property color rightColorResolved: pluginData.rightClickColor ? Qt.color(pluginData.rightClickColor) : Qt.color("#ffa502")
    readonly property color middleColorResolved: pluginData.middleClickColor ? Qt.color(pluginData.middleClickColor) : Qt.color("#00d2d3")

    // Drawing brush settings
    property string drawColor: pluginData.drawColor || "#ff4757"
    property real drawSize: Number(pluginData.drawSize) || 5
    property bool drawLaserMode: boolVal(pluginData.drawLaserMode, false)

    readonly property var paletteColors: [
        "#ff4757", // 1: Red
        "#ffa502", // 2: Amber/Yellow
        "#2ed573", // 3: Green
        "#1e90ff", // 4: Blue
        "#ff6b81", // 5: Pink/Magenta
        "#ffffff"  // 6: White
    ]

    // Signals for cross-screen synchronization
    signal clearAllDrawings()
    signal undoLastDrawing()
    signal clickTriggered(real gx, real gy, string btn)

    function savePluginSetting(key, value) {
        if (pluginService && pluginService.savePluginData) {
            pluginService.savePluginData(pluginId, key, value);
        }
    }

    function nudgeCursor() {
        Quickshell.execDetached([root.pluginDir + "/wl-nudge"]);
    }

    function requestInputPermissions() {
        const udevRule1 = 'SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_MOUSE}=="1", TAG+="uaccess"';
        const udevRule2 = 'SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_TOUCHPAD}=="1", TAG+="uaccess"';
        const cmd = "usermod -aG input $USER || true; " +
                    "printf '%s\\n%s\\n' '" + udevRule1 + "' '" + udevRule2 + "' > /etc/udev/rules.d/70-dms-cursor-spotlight.rules; " +
                    "udevadm control --reload-rules && udevadm trigger --subsystem-match=input || true; " +
                    "setfacl -m u:$USER:r /dev/input/event* || true";
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
        clicksActive = next;
        savePluginSetting("clicksActive", next);
        if (next) {
            nudgeTimer.restart();
            if (helperPermStatus === "NEEDS_PERM" && !permPromptShown) {
                permPromptShown = true;
                ToastService.showInfo("Autoriza el permiso de entrada para detectar los clicks del ratón");
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

    function spawnClickEffect(btn) {
        if (!hasCursorPos)
            return;
        const b = btn || "LEFT";
        if (b === "RIGHT") {
            activeClickColor = rightColorResolved;
        } else if (b === "MIDDLE") {
            activeClickColor = middleColorResolved;
        } else {
            activeClickColor = leftColorResolved;
        }
        haloPulseAnim.restart();
        root.clickTriggered(root.cursorX, root.cursorY, b);
    }

    // Growing / bounce animation for the cursor halo when clicking
    ParallelAnimation {
        id: haloPulseAnim

        SequentialAnimation {
            NumberAnimation {
                target: root
                property: "haloScale"
                from: 0.78
                to: root.haloTargetScale
                duration: 150
                easing.type: Easing.OutBack
                easing.overshoot: 2.2
            }
            NumberAnimation {
                target: root
                property: "haloScale"
                from: root.haloTargetScale
                to: 1.0
                duration: 260
                easing.type: Easing.OutCubic
            }
        }

        SequentialAnimation {
            NumberAnimation {
                target: root
                property: "clickFlash"
                from: 1.0
                to: 0.0
                duration: 380
                easing.type: Easing.OutQuad
            }
        }
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
                    const st = parts[1] || "OK";
                    root.helperPermStatus = st;
                    if (st === "NEEDS_PERM" && root.clicksActive && !root.permPromptShown) {
                        root.permPromptShown = true;
                        ToastService.showInfo("Autoriza el permiso una vez para animar los clicks del ratón");
                        root.requestInputPermissions();
                    }
                } else if (cmd === "DOWN") {
                    const btn = parts[1] || "LEFT";
                    root.mouseButtonHeld = true;
                    if (root.clicksActive || root.spotlightActive) {
                        root.spawnClickEffect(btn);
                    }
                } else if (cmd === "UP") {
                    root.mouseButtonHeld = false;
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

            // Active click ripples on this screen
            property var activeRipples: []

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

            // Compositor Background Blur (ext-background-effect-v1) with Spotlight circular cutout
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
                function onClickTriggered(gx, gy, btn) {
                    if (!root.showShockwave && !root.showRadialBurst)
                        return;
                    const lx = gx - win.modelData.x;
                    const ly = gy - win.modelData.y;
                    if (lx >= -100 && ly >= -100 && lx <= win.width + 100 && ly <= win.height + 100) {
                        const next = win.activeRipples.slice();
                        next.push({
                            "x": lx,
                            "y": ly,
                            "btn": btn,
                            "startTime": Date.now()
                        });
                        win.activeRipples = next;
                        rippleCanvas.requestPaint();
                    }
                }
            }

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
                property real sRadius: root.spotlightRadius * (1.0 + root.clickFlash * 0.12)
                property real dimAlpha: root.spotlightDimOpacity
                property color ringColor: root.clickFlash > 0.05 ? root.activeClickColor : root.spotlightColorResolved

                onCxChanged: if (visible) requestPaint()
                onCyChanged: if (visible) requestPaint()
                onOnScreenChanged: if (visible) requestPaint()
                onSRadiusChanged: if (visible) requestPaint()
                onDimAlphaChanged: if (visible) requestPaint()
                onRingColorChanged: if (visible) requestPaint()
                onVisibleChanged: if (visible) requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.save();
                    ctx.clearRect(0, 0, width, height);

                    ctx.beginPath();
                    ctx.rect(0, 0, width, height);
                    if (onScreen) {
                        ctx.arc(cx, cy, sRadius, 0, Math.PI * 2, true);
                    }
                    ctx.fillStyle = Qt.rgba(0, 0, 0, dimAlpha);
                    ctx.fill("evenodd");

                    if (onScreen && root.spotlightRingWidth > 0) {
                        ctx.beginPath();
                        ctx.arc(cx, cy, sRadius + 3, 0, Math.PI * 2);
                        ctx.strokeStyle = Qt.rgba(ringColor.r, ringColor.g, ringColor.b, 0.35 + root.clickFlash * 0.4);
                        ctx.lineWidth = root.spotlightRingWidth + 6;
                        ctx.stroke();

                        ctx.beginPath();
                        ctx.arc(cx, cy, sRadius, 0, Math.PI * 2);
                        ctx.strokeStyle = ringColor;
                        ctx.lineWidth = root.spotlightRingWidth + root.clickFlash * 2;
                        ctx.stroke();
                    }

                    ctx.restore();
                }
            }

            // 2. CURSOR HALO WITH GROW/PULSE EFFECT ON CLICK
            Rectangle {
                id: cursorHalo
                visible: root.clicksActive && root.showHaloWithClicks && win.cursorOnScreen && !root.drawActive
                readonly property real currentRadius: root.haloRadius * root.haloScale
                readonly property color baseColor: root.clickFlash > 0.05 ? root.activeClickColor : root.leftColorResolved

                x: win.localX - currentRadius
                y: win.localY - currentRadius
                width: currentRadius * 2
                height: currentRadius * 2
                radius: currentRadius
                color: Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.14 + root.clickFlash * 0.32)
                border.color: Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.8 + root.clickFlash * 0.2)
                border.width: 2.2 + root.clickFlash * 2.5

                Rectangle {
                    anchors.centerIn: parent
                    width: 6 + root.clickFlash * 8
                    height: width
                    radius: width / 2
                    color: cursorHalo.baseColor
                    opacity: 0.45 + root.clickFlash * 0.55
                }
            }

            // 3. HIGH-FPS CLICK SHOCKWAVE + RADIAL BURST CANVAS
            Canvas {
                id: rippleCanvas
                anchors.fill: parent
                visible: win.activeRipples.length > 0 && (root.showShockwave || root.showRadialBurst)

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.save();
                    ctx.clearRect(0, 0, width, height);

                    const now = Date.now();
                    const dur = root.rippleDuration;
                    const maxR = root.rippleSize;

                    for (let i = 0; i < win.activeRipples.length; i++) {
                        const r = win.activeRipples[i];
                        const p = Math.min(1.0, Math.max(0.0, (now - r.startTime) / dur));
                        if (p >= 1.0)
                            continue;

                        const ease = 1.0 - Math.pow(1.0 - p, 3);
                        const alpha = 1.0 - p;

                        let c = root.leftColorResolved;
                        if (r.btn === "RIGHT") {
                            c = root.rightColorResolved;
                        } else if (r.btn === "MIDDLE") {
                            c = root.middleColorResolved;
                        }

                        if (root.showShockwave) {
                            const outerR = 10 + (maxR - 10) * ease;
                            ctx.beginPath();
                            ctx.arc(r.x, r.y, outerR, 0, Math.PI * 2);
                            ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.24 * (1.0 - ease));
                            ctx.fill();
                            ctx.lineWidth = Math.max(1.5, 4.5 * alpha);
                            ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.95 * alpha);
                            ctx.stroke();

                            if (p > 0.1) {
                                const p2 = (p - 0.1) / 0.9;
                                const ease2 = 1.0 - Math.pow(1.0 - p2, 2);
                                const innerR = 6 + (maxR * 0.68) * ease2;
                                ctx.beginPath();
                                ctx.arc(r.x, r.y, innerR, 0, Math.PI * 2);
                                ctx.lineWidth = Math.max(1.0, 2.5 * (1.0 - p2));
                                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.75 * (1.0 - p2));
                                ctx.stroke();
                            }
                        }

                        if (root.showRadialBurst && p < 0.75) {
                            const rayP = p / 0.75;
                            const rayAlpha = 1.0 - rayP;
                            const rStart = 14 + (maxR * 0.55) * ease;
                            const rEnd = rStart + 10 * (1.0 - rayP * 0.5);
                            ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.85 * rayAlpha);
                            ctx.lineWidth = 2.2;
                            ctx.lineCap = "round";
                            for (let k = 0; k < 8; k++) {
                                const ang = (k * Math.PI) / 4;
                                ctx.beginPath();
                                ctx.moveTo(r.x + Math.cos(ang) * rStart, r.y + Math.sin(ang) * rStart);
                                ctx.lineTo(r.x + Math.cos(ang) * rEnd, r.y + Math.sin(ang) * rEnd);
                                ctx.stroke();
                            }
                        }
                    }

                    ctx.restore();
                }
            }

            Timer {
                id: rippleAnimTimer
                interval: 16
                repeat: true
                running: win.activeRipples.length > 0
                onTriggered: {
                    const now = Date.now();
                    const dur = root.rippleDuration;
                    const remaining = win.activeRipples.filter(r => (now - r.startTime) < dur);
                    if (remaining.length !== win.activeRipples.length) {
                        win.activeRipples = remaining;
                    }
                    rippleCanvas.requestPaint();
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
                            root.spawnClickEffect("LEFT");
                        }
                        let shapeMode = "free";
                        if (mouse.modifiers & Qt.ShiftModifier) {
                            shapeMode = "line";
                        } else if (mouse.modifiers & Qt.ControlModifier) {
                            shapeMode = "rect";
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
