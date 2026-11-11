import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.DCommon.Widgets
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
    property string drawTool: pluginData.drawTool || "free"

    readonly property var drawTools: [
        { "id": "free",   "icon": "brush",                  "label": "Pincel",   "key": "P" },
        { "id": "arrow",  "icon": "north_east",             "label": "Flecha",   "key": "A" },
        { "id": "circle", "icon": "radio_button_unchecked", "label": "Círculo",  "key": "O" },
        { "id": "rect",   "icon": "crop_square",            "label": "Cuadrado", "key": "R" }
    ]

    readonly property var paletteColors: [
        "#ff4757", // 1: Red
        "#ffa502", // 2: Amber/Yellow
        "#2ed573", // 3: Green
        "#1e90ff", // 4: Blue
        "#ff6b81", // 5: Pink/Magenta
        "#ffffff"  // 6: White
    ]

    onPluginDataChanged: {
        if (pluginData.drawColor)
            drawColor = String(pluginData.drawColor);
        if (pluginData.drawSize !== undefined)
            drawSize = Math.max(2, Math.min(32, Number(pluginData.drawSize) || 5));
        if (pluginData.drawLaserMode !== undefined)
            drawLaserMode = boolVal(pluginData.drawLaserMode, false);
        if (pluginData.drawTool)
            drawTool = String(pluginData.drawTool);
    }

    // Signals for cross-screen synchronization
    signal clearAllDrawings()
    signal undoLastDrawing()
    signal clickTriggered(real gx, real gy, string btn)

    function savePluginSetting(key, value) {
        if (pluginService && pluginService.savePluginData) {
            pluginService.savePluginData(pluginId, key, value);
        }
    }

    function setDrawSize(newSize) {
        const clamped = Math.max(2, Math.min(32, Math.round(newSize)));
        if (drawSize !== clamped) {
            drawSize = clamped;
            savePluginSetting("drawSize", clamped);
        }
    }

    function setDrawTool(toolId) {
        drawTool = toolId;
        savePluginSetting("drawTool", toolId);
    }

    function setDrawColor(hexColor) {
        drawColor = hexColor;
        savePluginSetting("drawColor", hexColor);
    }

    function toggleLaserMode() {
        drawLaserMode = !drawLaserMode;
        savePluginSetting("drawLaserMode", drawLaserMode);
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
                renderTarget: Canvas.FramebufferObject

                function renderStrokePath(ctx, s) {
                    const pts = s.points;
                    if ((s.shape === "rect" || s.shape === "circle" || s.shape === "arrow" || s.shape === "line") && pts.length >= 2) {
                        const p0 = pts[0];
                        const p1 = pts[pts.length - 1];
                        let dx = p1.x - p0.x;
                        let dy = p1.y - p0.y;

                        if (s.proportional && (s.shape === "rect" || s.shape === "circle")) {
                            const side = Math.max(Math.abs(dx), Math.abs(dy));
                            dx = (dx >= 0 ? 1 : -1) * side;
                            dy = (dy >= 0 ? 1 : -1) * side;
                        }

                        if (s.shape === "rect") {
                            ctx.strokeRect(p0.x, p0.y, dx, dy);
                        } else if (s.shape === "circle") {
                            const cx = p0.x + dx / 2;
                            const cy = p0.y + dy / 2;
                            const rx = Math.abs(dx) / 2;
                            const ry = Math.abs(dy) / 2;
                            if (rx > 0.5 && ry > 0.5) {
                                const k = 0.552284749831;
                                const ox = rx * k;
                                const oy = ry * k;
                                ctx.beginPath();
                                ctx.moveTo(cx - rx, cy);
                                ctx.bezierCurveTo(cx - rx, cy - oy, cx - ox, cy - ry, cx, cy - ry);
                                ctx.bezierCurveTo(cx + ox, cy - ry, cx + rx, cy - oy, cx + rx, cy);
                                ctx.bezierCurveTo(cx + rx, cy + oy, cx + ox, cy + ry, cx, cy + ry);
                                ctx.bezierCurveTo(cx - ox, cy + ry, cx - rx, cy + oy, cx - rx, cy);
                                ctx.closePath();
                                ctx.stroke();
                            }
                        } else {
                            const endX = p0.x + dx;
                            const endY = p0.y + dy;
                            const dist = Math.hypot(dx, dy);
                            if (dist > 2) {
                                const angle = Math.atan2(dy, dx);
                                const headLen = Math.min(dist * 0.85, Math.max(16, s.size * 3.6));
                                const shaftEndX = endX - Math.cos(angle) * (headLen * 0.5);
                                const shaftEndY = endY - Math.sin(angle) * (headLen * 0.5);

                                ctx.beginPath();
                                ctx.moveTo(p0.x, p0.y);
                                ctx.lineTo(shaftEndX, shaftEndY);
                                ctx.stroke();

                                ctx.beginPath();
                                ctx.moveTo(endX, endY);
                                ctx.lineTo(endX - headLen * Math.cos(angle - Math.PI / 6.2), endY - headLen * Math.sin(angle - Math.PI / 6.2));
                                ctx.lineTo(endX - (headLen * 0.72) * Math.cos(angle), endY - (headLen * 0.72) * Math.sin(angle));
                                ctx.lineTo(endX - headLen * Math.cos(angle + Math.PI / 6.2), endY - headLen * Math.sin(angle + Math.PI / 6.2));
                                ctx.closePath();
                                ctx.fill();
                            }
                        }
                    } else if (pts.length === 1) {
                        if (s.shape === "free" || !s.shape) {
                            ctx.beginPath();
                            ctx.arc(pts[0].x, pts[0].y, Math.max(1, s.size / 2), 0, Math.PI * 2);
                            ctx.fill();
                        }
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
                }

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

                        if (s.laser) {
                            // Fast vector-based glow (100x faster than CPU shadowBlur)
                            // 1. Soft outer neon glow
                            ctx.save();
                            ctx.globalAlpha = alpha * 0.25;
                            ctx.strokeStyle = s.color;
                            ctx.fillStyle = s.color;
                            ctx.lineWidth = s.size * 2.2;
                            drawCanvas.renderStrokePath(ctx, s);
                            ctx.restore();

                            // 2. Main vivid beam
                            ctx.save();
                            ctx.globalAlpha = alpha * 0.95;
                            ctx.strokeStyle = s.color;
                            ctx.fillStyle = s.color;
                            ctx.lineWidth = s.size;
                            drawCanvas.renderStrokePath(ctx, s);
                            ctx.restore();

                            // 3. Bright core highlight
                            ctx.save();
                            ctx.globalAlpha = alpha * 0.75;
                            ctx.strokeStyle = "#ffffff";
                            ctx.fillStyle = "#ffffff";
                            ctx.lineWidth = Math.max(1.5, s.size * 0.32);
                            drawCanvas.renderStrokePath(ctx, s);
                            ctx.restore();
                        } else {
                            ctx.save();
                            ctx.globalAlpha = alpha;
                            ctx.strokeStyle = s.color;
                            ctx.fillStyle = s.color;
                            ctx.lineWidth = s.size;
                            drawCanvas.renderStrokePath(ctx, s);
                            ctx.restore();
                        }
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
                        if (win.currentStroke.shape === "free") {
                            const pts = win.currentStroke.points;
                            const lastPt = pts[pts.length - 1];
                            const dx = mouse.x - lastPt.x;
                            const dy = mouse.y - lastPt.y;
                            if ((dx * dx + dy * dy) >= 9) { // 3px minimum delta prevents high-polling rate mouse event lag
                                pts.push({ "x": mouse.x, "y": mouse.y });
                                win.currentStroke.updatedAt = Date.now();
                                drawCanvas.requestPaint();
                            }
                        } else {
                            win.currentStroke.points = [win.currentStroke.points[0], { "x": mouse.x, "y": mouse.y }];
                            win.currentStroke.proportional = (root.drawTool !== "free") && Boolean(mouse.modifiers & Qt.ShiftModifier);
                            win.currentStroke.updatedAt = Date.now();
                            drawCanvas.requestPaint();
                        }
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
                        let shapeMode = root.drawTool || "free";
                        let proportional = false;
                        if (shapeMode === "free") {
                            if (mouse.modifiers & Qt.ShiftModifier) {
                                shapeMode = "arrow";
                            } else if (mouse.modifiers & Qt.ControlModifier) {
                                shapeMode = "rect";
                            } else if (mouse.modifiers & Qt.AltModifier) {
                                shapeMode = "circle";
                            }
                        } else {
                            proportional = Boolean(mouse.modifiers & Qt.ShiftModifier);
                        }
                        win.currentStroke = {
                            "points": [{ "x": mouse.x, "y": mouse.y }],
                            "color": root.drawColor,
                            "size": root.drawSize,
                            "laser": root.drawLaserMode,
                            "shape": shapeMode,
                            "proportional": proportional,
                            "updatedAt": Date.now()
                        };
                        drawCanvas.requestPaint();
                    }
                }

                onReleased: mouse => {
                    if (mouse.button === Qt.LeftButton && win.currentStroke) {
                        const s = win.currentStroke;
                        s.updatedAt = Date.now();
                        const validShape = s.shape === "free" || (s.points.length >= 2 && Math.hypot(s.points[s.points.length - 1].x - s.points[0].x, s.points[s.points.length - 1].y - s.points[0].y) >= 3);
                        if (validShape) {
                            const next = win.strokes.slice();
                            next.push(s);
                            win.strokes = next;
                        }
                        win.currentStroke = null;
                        drawCanvas.requestPaint();
                    }
                }

                onWheel: wheel => {
                    const delta = wheel.angleDelta.y > 0 ? 1 : -1;
                    root.setDrawSize(root.drawSize + delta);
                }
            }

            Rectangle {
                visible: root.drawActive && win.cursorOnScreen
                x: win.localX - width / 2
                y: win.localY - height / 2
                width: Math.max(8, root.drawSize + 4)
                height: Math.max(8, root.drawSize + 4)
                radius: root.drawTool === "rect" ? 2 : width / 2
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
                        root.toggleLaserMode();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_B) {
                        root.toggleSpotlight();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_P || event.key === Qt.Key_F) {
                        root.setDrawTool("free");
                        event.accepted = true;
                    } else if (event.key === Qt.Key_A) {
                        root.setDrawTool("arrow");
                        event.accepted = true;
                    } else if (event.key === Qt.Key_O || event.key === Qt.Key_E) {
                        root.setDrawTool("circle");
                        event.accepted = true;
                    } else if (event.key === Qt.Key_R) {
                        root.setDrawTool("rect");
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Minus || event.key === Qt.Key_BracketLeft) {
                        root.setDrawSize(root.drawSize - 2);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal || event.key === Qt.Key_BracketRight) {
                        root.setDrawSize(root.drawSize + 2);
                        event.accepted = true;
                    } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_6) {
                        const idx = event.key - Qt.Key_1;
                        if (idx >= 0 && idx < root.paletteColors.length) {
                            root.setDrawColor(root.paletteColors[idx]);
                        }
                        event.accepted = true;
                    }
                }
            }

            // Floating Paint HUD Toolbar for Draw Mode
            Rectangle {
                id: drawHud
                visible: root.drawActive && win.cursorOnScreen
                anchors.top: parent.top
                anchors.topMargin: 22
                anchors.horizontalCenter: parent.horizontalCenter
                width: hudCol.implicitWidth + 32
                height: hudCol.implicitHeight + 22
                radius: 22
                color: Qt.rgba(0.07, 0.08, 0.11, 0.94)
                border.color: Qt.rgba(1, 1, 1, 0.18)
                border.width: 1

                // Prevent clicks inside the HUD from drawing on the canvas behind it
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.AllButtons
                    onPositionChanged: mouse => {
                        const pt = drawHud.mapToItem(null, mouse.x, mouse.y);
                        root.cursorX = win.modelData.x + pt.x;
                        root.cursorY = win.modelData.y + pt.y;
                    }
                    onWheel: wheel => {
                        const delta = wheel.angleDelta.y > 0 ? 1 : -1;
                        root.setDrawSize(root.drawSize + delta);
                    }
                }

                Column {
                    id: hudCol
                    anchors.centerIn: parent
                    spacing: 8

                    // ROW 1: Tools (Pincel, Flecha, Círculo, Cuadrado) + Grosor + Colores
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        // Shape / Tool selector buttons
                        Row {
                            spacing: 5
                            anchors.verticalCenter: parent.verticalCenter

                            Repeater {
                                model: root.drawTools

                                Rectangle {
                                    required property var modelData
                                    readonly property bool isSelected: root.drawTool === modelData.id
                                    height: 32
                                    width: toolRow.implicitWidth + 18
                                    radius: 16
                                    color: isSelected ? Qt.rgba(0.18, 0.56, 1.0, 0.38) : Qt.rgba(1, 1, 1, 0.08)
                                    border.color: isSelected ? "#4dabf7" : Qt.rgba(1, 1, 1, 0.12)
                                    border.width: isSelected ? 1.5 : 1

                                    Row {
                                        id: toolRow
                                        anchors.centerIn: parent
                                        spacing: 5

                                        DIcon {
                                            name: modelData.icon
                                            size: 16
                                            color: isSelected ? "#ffffff" : "#d0d7de"
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Text {
                                            text: modelData.label + " (" + modelData.key + ")"
                                            color: isSelected ? "#ffffff" : "#d0d7de"
                                            font.pixelSize: 12
                                            font.bold: isSelected
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setDrawTool(modelData.id)
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: 1
                            height: 24
                            color: Qt.rgba(1, 1, 1, 0.2)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Thickness (Grosor) interactive control: [ - ] [ slider + preview ] [ + ]
                        Row {
                            spacing: 5
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                width: 28
                                height: 28
                                radius: 14
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.rgba(1, 1, 1, 0.1)

                                DIcon {
                                    anchors.centerIn: parent
                                    name: "remove"
                                    size: 16
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setDrawSize(root.drawSize - 2)
                                }
                            }

                            Rectangle {
                                id: sizeSliderPill
                                width: 132
                                height: 30
                                radius: 15
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.rgba(1, 1, 1, 0.07)
                                border.color: Qt.rgba(1, 1, 1, 0.14)
                                border.width: 1

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 7

                                    // Live brush dot preview
                                    Item {
                                        width: 20
                                        height: 20
                                        anchors.verticalCenter: parent.verticalCenter

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: Math.max(4, Math.min(20, root.drawSize * 0.65))
                                            height: width
                                            radius: width / 2
                                            color: root.drawColor
                                            border.color: "#ffffff"
                                            border.width: 1
                                        }
                                    }

                                    // Interactive slider track
                                    Item {
                                        id: sizeTrack
                                        width: 58
                                        height: 22
                                        anchors.verticalCenter: parent.verticalCenter

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width
                                            height: 6
                                            radius: 3
                                            color: Qt.rgba(1, 1, 1, 0.2)

                                            Rectangle {
                                                width: Math.max(4, ((root.drawSize - 2) / 30.0) * parent.width)
                                                height: parent.height
                                                radius: 3
                                                color: root.drawColor
                                            }
                                        }

                                        Rectangle {
                                            width: 12
                                            height: 12
                                            radius: 6
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: Math.max(0, Math.min(parent.width - width, ((root.drawSize - 2) / 30.0) * (parent.width - width)))
                                            color: "#ffffff"
                                            border.color: Qt.rgba(0, 0, 0, 0.4)
                                            border.width: 1
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            function updateFromMouse(mx) {
                                                const ratio = Math.max(0.0, Math.min(1.0, mx / sizeTrack.width));
                                                root.setDrawSize(2 + ratio * 30);
                                            }
                                            onPressed: mouse => updateFromMouse(mouse.x)
                                            onPositionChanged: mouse => {
                                                if (pressed)
                                                    updateFromMouse(mouse.x);
                                            }
                                        }
                                    }

                                    Text {
                                        text: Math.round(root.drawSize) + "px"
                                        color: "#ffffff"
                                        font.pixelSize: 11
                                        font.bold: true
                                        width: 28
                                        horizontalAlignment: Text.AlignRight
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                            Rectangle {
                                width: 28
                                height: 28
                                radius: 14
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.rgba(1, 1, 1, 0.1)

                                DIcon {
                                    anchors.centerIn: parent
                                    name: "add"
                                    size: 16
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setDrawSize(root.drawSize + 2)
                                }
                            }
                        }

                        Rectangle {
                            width: 1
                            height: 24
                            color: Qt.rgba(1, 1, 1, 0.2)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Color Palette (1 - 6)
                        Row {
                            spacing: 7
                            anchors.verticalCenter: parent.verticalCenter

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
                                        onClicked: root.setDrawColor(modelData)
                                    }
                                }
                            }
                        }
                    }

                    // ROW 2: Mode toggles (Láser/Fijo, Blur), History (Deshacer, Limpiar), Salir & Quick Hint
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        Rectangle {
                            height: 28
                            width: laserLabel.implicitWidth + 18
                            radius: 14
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.drawLaserMode ? Qt.rgba(1, 0.28, 0.34, 0.35) : Qt.rgba(1, 1, 1, 0.08)
                            border.color: root.drawLaserMode ? "#ff4757" : "transparent"
                            border.width: 1

                            Text {
                                id: laserLabel
                                anchors.centerIn: parent
                                text: root.drawLaserMode ? "Modo: Láser (L)" : "Modo: Fijo (L)"
                                color: "#ffffff"
                                font.pixelSize: 11
                                font.bold: root.drawLaserMode
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleLaserMode()
                            }
                        }

                        Rectangle {
                            height: 28
                            width: blurLabel.implicitWidth + 18
                            radius: 14
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.spotlightActive ? Qt.rgba(0.12, 0.56, 1.0, 0.35) : Qt.rgba(1, 1, 1, 0.08)
                            border.color: root.spotlightActive ? "#1e90ff" : "transparent"
                            border.width: 1

                            Text {
                                id: blurLabel
                                anchors.centerIn: parent
                                text: "Spotlight Blur (B)"
                                color: "#ffffff"
                                font.pixelSize: 11
                                font.bold: root.spotlightActive
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleSpotlight()
                            }
                        }

                        Rectangle {
                            height: 28
                            width: undoLabel.implicitWidth + 18
                            radius: 14
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.rgba(1, 1, 1, 0.08)

                            Text {
                                id: undoLabel
                                anchors.centerIn: parent
                                text: "Deshacer (Z / Click Der)"
                                color: "#ffffff"
                                font.pixelSize: 11
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.undoLastDrawing()
                            }
                        }

                        Rectangle {
                            height: 28
                            width: clearLabel.implicitWidth + 18
                            radius: 14
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.rgba(1, 1, 1, 0.08)

                            Text {
                                id: clearLabel
                                anchors.centerIn: parent
                                text: "Limpiar (C)"
                                color: "#ffffff"
                                font.pixelSize: 11
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.clearAllDrawings()
                            }
                        }

                        Rectangle {
                            height: 28
                            width: exitLabel.implicitWidth + 18
                            radius: 14
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.rgba(1, 0.3, 0.3, 0.25)

                            Text {
                                id: exitLabel
                                anchors.centerIn: parent
                                text: "Salir (Esc)"
                                color: "#ff9999"
                                font.pixelSize: 11
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
}
