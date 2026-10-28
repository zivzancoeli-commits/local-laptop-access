var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
import "./polyfill/index.js";
import { apiGetRole, getApi } from "./api.js";
import { showNotification } from "./component/notification.js";
import { Stream } from "./stream/index.js?v=snd1";
import { getModalBackground, showMessage, showModal } from "./component/modal/index.js";
import { getSidebarRoot, setSidebar, setSidebarExtended, setSidebarStyle } from "./component/sidebar/index.js";
import { defaultStreamInputConfig } from "./stream/input.js?v=look1";
import { getLocalStreamSettings, setLocalStreamSettings } from "./component/settings_menu.js";
import { SelectComponent } from "./component/input.js";
import { StreamKeys } from "./api_bindings.js";
import { ScreenKeyboard } from "./screen_keyboard.js";
import { FormModal } from "./component/modal/form.js";
import { adoptRoleDefaultLanguage, getCurrentLanguage, getTranslations } from "./i18n.js";
import { applyAudioBufferProfile, applySoundToPage, applyViewModeSettings, getMaxFps, getSoundOn, getViewMode, MAX_FPS_OPTIONS, setMaxFps, setSoundOn, setViewMode, VIEW_MODE_HINTS, VIEW_MODE_LABELS, VIEW_MODES } from "./view_mode.js?v=snd1";
import { resolveHostSession } from "./host_session.js";
let I = getTranslations(getCurrentLanguage());
function startApp() {
    return __awaiter(this, void 0, void 0, function* () {
        const api = yield getApi();
        const bootstrapRole = yield apiGetRole(api, { id: null });
        adoptRoleDefaultLanguage(bootstrapRole.role.default_settings);
        I = getTranslations(getCurrentLanguage());
        const rootElement = document.getElementById("root");
        if (rootElement == null) {
            showNotification(I.stream.rootNotFound, "error");
            return;
        }
        // Get Host and App via Query, or this computer's Desktop session.
        const queryParams = new URLSearchParams(location.search);
        let hostIdStr = queryParams.get("hostId");
        let appIdStr = queryParams.get("appId");
        if (hostIdStr == null || appIdStr == null) {
            const session = yield resolveHostSession(api);
            if (!session) {
                yield showMessage(I.stream.missingHostOrApp);
                window.close();
                return;
            }
            hostIdStr = String(session.hostId);
            appIdStr = String(session.appId);
            const url = new URL(window.location.href);
            url.searchParams.set("hostId", hostIdStr);
            url.searchParams.set("appId", appIdStr);
            window.history.replaceState(null, "", url);
        }
        const hostId = Number.parseInt(hostIdStr);
        const appId = Number.parseInt(appIdStr);
        // event propagation on overlays
        const sidebarRoot = getSidebarRoot();
        if (sidebarRoot) {
            stopPropagationOn(sidebarRoot);
        }
        const modalBackground = getModalBackground();
        if (modalBackground) {
            stopPropagationOn(modalBackground);
        }
        // Start and Mount App
        const app = new ViewerApp(api, hostId, appId, bootstrapRole.role);
        app.mount(rootElement);
        window["app"] = app;
    });
}
// Prevent starting transition
window.requestAnimationFrame(() => {
    var _a;
    // Note: elements is a live array
    const elements = document.getElementsByClassName("prevent-start-transition");
    while (elements.length > 0) {
        (_a = elements.item(0)) === null || _a === void 0 ? void 0 : _a.classList.remove("prevent-start-transition");
    }
});
startApp();
class ViewerApp {
    constructor(api, hostId, appId, bootstrapRole) {
        this.div = document.createElement("div");
        this.statsDiv = document.createElement("div");
        this.localTouchCursorDiv = document.createElement("div");
        this.inputConfig = defaultStreamInputConfig();
        this.autoEnterFullscreenOnStart = false;
        this.pendingAutoFullscreenPrompt = false;
        this.fullscreenPromptShown = false;
        this.fullscreenOnNextInteractionArmed = false;
        this.pendingAutoFullscreenTouchGesture = false;
        this.pendingAutoFullscreenMouseGesture = false;
        this.manualFullscreenExitRequested = false;
        this.toggleFullscreenWithKeybind = false;
        this.hasShownFullscreenEscapeWarning = false;
        this.keyboardViewportBaselineHeight = null;
        this.streamVideoTopOffsetPx = 0;
        this.inputLoopsStarted = false;
        this.switchingMode = false;
        this.isTogglingFullscreenWithKeybind = "none";
        this.api = api;
        this.hostId = hostId;
        this.appId = appId;
        this.permissions = bootstrapRole.permissions;
        this.roleDefaults = bootstrapRole.default_settings;
        const viewMode = getViewMode();
        const settings = applyViewModeSettings(getLocalStreamSettings(bootstrapRole.default_settings), viewMode);
        setLocalStreamSettings(settings);
        applyAudioBufferProfile(viewMode);
        applySoundToPage(getSoundOn() && viewMode !== "sleep");
        Object.assign(this.inputConfig, {
            mouseMode: settings.mouseMode,
            mouseScrollMode: settings.mouseScrollMode,
            touchMode: settings.touchMode,
            localCursorSensitivity: settings.localCursorSensitivity,
            controllerConfig: settings.controllerConfig
        });
        // Configure sidebar as a always-visible options bar until fullscreen.
        this.sidebar = new ViewerSidebar(this);
        setSidebar(this.sidebar);
        setSidebarStyle({ edge: "up" });
        setSidebarExtended(true);
        // Configure stats element
        this.statsDiv.hidden = true;
        this.statsDiv.classList.add("video-stats");
        this.localTouchCursorDiv.hidden = true;
        this.localTouchCursorDiv.classList.add("local-touch-cursor");
        setInterval(() => {
            var _a;
            const stats = (_a = this.getStream()) === null || _a === void 0 ? void 0 : _a.getStats();
            if (stats) {
                if (!stats.isEnabled()) {
                    stats.setEnabled(true);
                }
                this.statsDiv.hidden = true;
                this.sidebar.updateLiveStats(stats.getCurrentStats());
            }
        }, 500);
        this.div.appendChild(this.statsDiv);
        this.div.appendChild(this.localTouchCursorDiv);
        // Configure stream
        this.previousMouseMode = this.inputConfig.mouseMode;
        const browserWidth = Math.max(document.documentElement.clientWidth || 0, window.innerWidth || 0);
        const browserHeight = Math.max(document.documentElement.clientHeight || 0, window.innerHeight || 0);
        this.autoEnterFullscreenOnStart = settings.enterFullscreenOnStreamStart;
        this.toggleFullscreenWithKeybind = settings.toggleFullscreenWithKeybind;
        this.stream = new Stream(this.api, hostId, appId, settings, [browserWidth, browserHeight], bootstrapRole.permissions);
        this.stream.getStats().setEnabled(true);
        this.startStream(hostId, appId, bootstrapRole.permissions, settings, [browserWidth, browserHeight]);
        // Configure input
        this.addListeners(document);
        this.addListeners(document.getElementById("input"));
        window.addEventListener("blur", () => {
            this.stream.getInput().raiseAllKeys();
        });
        document.addEventListener("visibilitychange", () => {
            if (document.visibilityState !== "visible") {
                this.stream.getInput().raiseAllKeys();
            }
        });
        document.addEventListener("pointerlockchange", this.onPointerLockChange.bind(this));
        document.addEventListener("fullscreenchange", this.onFullscreenChange.bind(this));
        window.addEventListener("resize", () => this.syncToolbarLayout());
        this.checkFullyImmersed();
        window.addEventListener("gamepadconnected", this.onGamepadConnect.bind(this));
        window.addEventListener("gamepaddisconnected", this.onGamepadDisconnect.bind(this));
        // Connect all gamepads
        for (const gamepad of navigator.getGamepads()) {
            if (gamepad != null) {
                this.onGamepadAdd(gamepad);
            }
        }
    }
    addListeners(element) {
        element.addEventListener("keydown", this.onKeyDown.bind(this), { passive: false });
        element.addEventListener("keyup", this.onKeyUp.bind(this), { passive: false });
        element.addEventListener("paste", this.onPaste.bind(this));
        element.addEventListener("mousedown", this.onMouseButtonDown.bind(this), { passive: false });
        element.addEventListener("mouseup", this.onMouseButtonUp.bind(this), { passive: false });
        element.addEventListener("mousemove", this.onMouseMove.bind(this), { passive: false });
        element.addEventListener("wheel", this.onMouseWheel.bind(this), { passive: false });
        element.addEventListener("contextmenu", this.onContextMenu.bind(this), { passive: false });
        element.addEventListener("touchstart", this.onTouchStart.bind(this), { passive: false });
        element.addEventListener("touchend", this.onTouchEnd.bind(this), { passive: false });
        element.addEventListener("touchcancel", this.onTouchCancel.bind(this), { passive: false });
        element.addEventListener("touchmove", this.onTouchMove.bind(this), { passive: false });
    }
    startStream(hostId, appId, permissions, settings, browserSize) {
        return __awaiter(this, void 0, void 0, function* () {
            setSidebarStyle({
                edge: "up",
            });
            setSidebarExtended(true);
            // Add app info listener
            this.stream.addInfoListener(this.onInfo.bind(this));
            const connectionInfo = new ConnectionInfoModal(() => { void this.reconnectStream(); });
            const connectionInfoListener = (event) => {
                connectionInfo.onInfo(event);
                const data = event.detail;
                if (data.type == "videoReady") {
                    this.stream.removeInfoListener(connectionInfoListener);
                    if (this.autoEnterFullscreenOnStart && this.pendingAutoFullscreenPrompt && !this.fullscreenPromptShown && !this.isFullscreen()) {
                        this.fullscreenPromptShown = true;
                        this.pendingAutoFullscreenPrompt = false;
                        this.armFullscreenOnNextInteraction();
                    }
                }
                else if (data.type == "addDebugLine" && (data.additional?.type == "fatal" || data.additional?.type == "fatalDescription")) {
                    void showModal(connectionInfo);
                }
            };
            this.stream.addInfoListener(connectionInfoListener);
            if (!this.inputLoopsStarted) {
                this.inputLoopsStarted = true;
                this.onTouchUpdate();
                this.onGamepadUpdate();
            }
            this.stream.getInput().addScreenKeyboardVisibleEvent(this.onScreenKeyboardSetVisible.bind(this));
            this.stream.mount(this.div);
            this.stream.getStats().setEnabled(true);
            if (this.autoEnterFullscreenOnStart) {
                this.pendingAutoFullscreenPrompt = true;
            }
            this.applyMouseLookConfig();
        });
    }
    onInfo(event) {
        return __awaiter(this, void 0, void 0, function* () {
            const data = event.detail;
            if (data.type == "app") {
                const app = data.app;
                document.title = `Stream: ${app.title}`;
            }
            else if (data.type == "connectionComplete") {
                this.sidebar.onCapabilitiesChange(data.capabilities);
            }
            else if (data.type == "videoReady") {
                if (getSoundOn() && getViewMode() !== "sleep") {
                    this.onUserInteraction();
                    applySoundToPage(true);
                }
            }
        });
    }
    focusInput() {
        if (this.stream.getInput().getCurrentPredictedTouchAction() != "screenKeyboard" && !this.sidebar.getScreenKeyboard().isVisible()) {
            const inputElement = document.getElementById("input");
            inputElement.focus();
        }
    }
    onUserInteraction() {
        var _a, _b;
        this.focusInput();
        (_a = this.stream.getVideoRenderer()) === null || _a === void 0 ? void 0 : _a.onUserInteraction();
        if (getSoundOn() && getViewMode() !== "sleep") {
            (_b = this.stream.getAudioPlayer()) === null || _b === void 0 ? void 0 : _b.onUserInteraction();
        }
        else {
            applySoundToPage(false);
            this.stream.setAudioEnabled(false);
        }
    }
    switchViewMode(mode) {
        return __awaiter(this, void 0, void 0, function* () {
            if (this.switchingMode || getViewMode() === mode) {
                return;
            }
            this.switchingMode = true;
            this.sidebar.updateModeButtons();
            this.sidebar.updateReconnectButton();
            try {
                setViewMode(mode);
                if (mode === "sleep") {
                    setSoundOn(false);
                }
                const settings = applyViewModeSettings(getLocalStreamSettings(this.roleDefaults), mode);
                setLocalStreamSettings(settings);
                applyAudioBufferProfile(mode);
                applySoundToPage(getSoundOn() && mode !== "sleep");
                yield this.replaceStream(settings);
                if (getSoundOn() && mode !== "sleep") {
                    this.onUserInteraction();
                }
            }
            finally {
                this.switchingMode = false;
                this.sidebar.updateModeButtons();
                this.sidebar.updateSoundButton();
                this.sidebar.updateMaxFpsControl();
                this.sidebar.updateReconnectButton();
                requestAnimationFrame(() => this.syncToolbarLayout());
            }
        });
    }
    switchMaxFps(fps) {
        return __awaiter(this, void 0, void 0, function* () {
            if (this.switchingMode || getMaxFps() === fps) {
                this.sidebar.updateMaxFpsControl();
                return;
            }
            this.switchingMode = true;
            this.sidebar.updateMaxFpsControl();
            this.sidebar.updateReconnectButton();
            try {
                setMaxFps(fps);
                const mode = getViewMode();
                const settings = applyViewModeSettings(getLocalStreamSettings(this.roleDefaults), mode);
                setLocalStreamSettings(settings);
                yield this.replaceStream(settings);
            }
            finally {
                this.switchingMode = false;
                this.sidebar.updateModeButtons();
                this.sidebar.updateMaxFpsControl();
                this.sidebar.updateReconnectButton();
                requestAnimationFrame(() => this.syncToolbarLayout());
            }
        });
    }
    replaceStream(settings) {
        return __awaiter(this, void 0, void 0, function* () {
            const oldStream = this.stream;
            try {
                yield oldStream.stop();
            }
            catch (error) {
                console.warn("failed to stop stream for reconnect", error);
            }
            try {
                oldStream.unmount(this.div);
            }
            catch (error) {
                console.warn("failed to unmount stream for reconnect", error);
            }
            const browserWidth = Math.max(document.documentElement.clientWidth || 0, window.innerWidth || 0);
            const browserHeight = Math.max(document.documentElement.clientHeight || 0, window.innerHeight || 0);
            this.stream = new Stream(this.api, this.hostId, this.appId, settings, [browserWidth, browserHeight], this.permissions);
            this.stream.getStats().setEnabled(true);
            yield this.startStream(this.hostId, this.appId, this.permissions, settings, [browserWidth, browserHeight]);
            this.applyMouseLookConfig();
        });
    }
    toggleSound() {
        const next = !getSoundOn();
        setSoundOn(next);
        this.stream.setAudioEnabled(next);
        if (next) {
            this.onUserInteraction();
        }
        else {
            applySoundToPage(false);
        }
        this.sidebar.updateSoundButton();
    }
    isReconnecting() {
        return this.switchingMode;
    }
    reconnectStream() {
        return __awaiter(this, void 0, void 0, function* () {
            if (this.switchingMode) {
                return;
            }
            this.switchingMode = true;
            this.sidebar.updateReconnectButton();
            try {
                showModal(null);
                const settings = applyViewModeSettings(getLocalStreamSettings(this.roleDefaults), getViewMode());
                setLocalStreamSettings(settings);
                yield this.replaceStream(settings);
                if (getSoundOn() && getViewMode() !== "sleep") {
                    this.onUserInteraction();
                }
                else {
                    applySoundToPage(false);
                    this.stream.setAudioEnabled(false);
                }
            }
            catch (error) {
                console.warn("failed to reconnect stream", error);
            }
            finally {
                this.switchingMode = false;
                this.sidebar.updateModeButtons();
                this.sidebar.updateSoundButton();
                this.sidebar.updateMaxFpsControl();
                this.sidebar.updateReconnectButton();
                requestAnimationFrame(() => this.syncToolbarLayout());
            }
        });
    }
    captureFullscreenMouse() {
        return __awaiter(this, void 0, void 0, function* () {
            if (!this.isFullscreen()) {
                return;
            }
            yield this.requestPointerLock();
        });
    }
    applyMouseLookConfig() {
        const locked = !!document.pointerLockElement;
        this.inputConfig.mouseMode = locked ? "relative" : "follow";
        this.setInputConfig(this.inputConfig);
        document.body.classList.toggle("stream-pointer-locked", locked);
        this.sidebar.updateGameMouseButton();
    }
    isStreamChromeEvent(event) {
        const target = event.target;
        if (!(target instanceof Element)) {
            return false;
        }
        return !!target.closest(".sidebar-overlay, .stream-sound-floating, .stream-mouse-floating, .modal-background");
    }
    armFullscreenOnNextInteraction() {
        if (this.autoEnterFullscreenOnStart) {
            this.fullscreenOnNextInteractionArmed = true;
        }
    }
    consumeAutoFullscreenInteraction() {
        if (!this.fullscreenOnNextInteractionArmed || this.isFullscreen()) {
            return false;
        }
        this.fullscreenOnNextInteractionArmed = false;
        void this.requestFullscreen().then(() => {
            if (!this.isFullscreen()) {
                this.armFullscreenOnNextInteraction();
            }
        });
        return true;
    }
    beginAutoFullscreenTouchGesture() {
        if (!this.fullscreenOnNextInteractionArmed || this.isFullscreen()) {
            return false;
        }
        this.pendingAutoFullscreenTouchGesture = true;
        return true;
    }
    consumeAutoFullscreenTouchGesture() {
        if (!this.pendingAutoFullscreenTouchGesture) {
            return false;
        }
        this.pendingAutoFullscreenTouchGesture = false;
        return this.consumeAutoFullscreenInteraction();
    }
    onScreenKeyboardSetVisible(event) {
        console.info(event.detail);
        const screenKeyboard = this.sidebar.getScreenKeyboard();
        const newShown = event.detail.visible;
        if (newShown != screenKeyboard.isVisible()) {
            if (newShown) {
                screenKeyboard.show();
            }
            else {
                screenKeyboard.hide();
            }
        }
    }
    // Input
    getInputConfig() {
        return this.inputConfig;
    }
    setInputConfig(config) {
        Object.assign(this.inputConfig, config);
        this.stream.getInput().setConfig(this.inputConfig);
        this.renderLocalTouchCursor();
    }
    // Keyboard
    onKeyDown(event) {
        this.onUserInteraction();
        console.debug(event);
        if (event.shiftKey && event.ctrlKey && event.code == "KeyV") {
            // We are likely pasting -> don't send keys
        }
        else if (event.code == "F11") {
            // Allow manual fullscreen
        }
        else {
            event.preventDefault();
            this.stream.getInput().onKeyDown(event);
        }
        event.stopPropagation();
    }
    onKeyUp(event) {
        this.onUserInteraction();
        event.preventDefault();
        this.stream.getInput().onKeyUp(event);
        event.stopPropagation();
        if (this.toggleFullscreenWithKeybind && this.isTogglingFullscreenWithKeybind == "none" && event.ctrlKey && event.shiftKey && event.code == "KeyI") {
            this.isTogglingFullscreenWithKeybind = "waitForCtrl";
        }
        if (this.isTogglingFullscreenWithKeybind == "waitForCtrl" && (event.code == "ControlRight" || event.code == "ControlLeft")) {
            this.isTogglingFullscreenWithKeybind = "makingFullscreen";
            (() => __awaiter(this, void 0, void 0, function* () {
                if (this.isFullscreen()) {
                    yield this.exitPointerLock();
                    yield this.exitFullscreen();
                }
                else {
                    yield this.requestFullscreen();
                    yield this.requestPointerLock();
                }
                this.isTogglingFullscreenWithKeybind = "none";
            }))();
        }
    }
    onPaste(event) {
        this.onUserInteraction();
        this.stream.getInput().onPaste(event);
        event.stopPropagation();
    }
    // Mouse
    onMouseButtonDown(event) {
        if (this.consumeAutoFullscreenInteraction()) {
            this.pendingAutoFullscreenMouseGesture = true;
            event.preventDefault();
            event.stopPropagation();
            return;
        }
        this.onUserInteraction();
        event.preventDefault();
        this.stream.getInput().onMouseDown(event, this.getStreamRect());
        event.stopPropagation();
        if (this.isFullscreen() && !document.pointerLockElement && !this.isStreamChromeEvent(event)) {
            void this.requestPointerLock();
        }
    }
    onMouseButtonUp(event) {
        if (this.pendingAutoFullscreenMouseGesture) {
            this.pendingAutoFullscreenMouseGesture = false;
            event.preventDefault();
            event.stopPropagation();
            return;
        }
        this.onUserInteraction();
        event.preventDefault();
        this.stream.getInput().onMouseUp(event);
        event.stopPropagation();
    }
    onMouseMove(event) {
        if (this.pendingAutoFullscreenMouseGesture) {
            event.preventDefault();
            event.stopPropagation();
            return;
        }
        event.preventDefault();
        this.stream.getInput().onMouseMove(event, this.getStreamRect());
        event.stopPropagation();
    }
    onMouseWheel(event) {
        event.preventDefault();
        this.stream.getInput().onMouseWheel(event);
        event.stopPropagation();
    }
    onContextMenu(event) {
        event.preventDefault();
        event.stopPropagation();
    }
    // Touch
    onTouchStart(event) {
        if (this.beginAutoFullscreenTouchGesture()) {
            event.preventDefault();
            event.stopPropagation();
            return;
        }
        this.onUserInteraction();
        event.preventDefault();
        this.stream.getInput().onTouchStart(event, this.getStreamRect());
        event.stopPropagation();
    }
    onTouchEnd(event) {
        if (this.consumeAutoFullscreenTouchGesture()) {
            event.preventDefault();
            event.stopPropagation();
            return;
        }
        this.onUserInteraction();
        event.preventDefault();
        this.stream.getInput().onTouchEnd(event, this.getStreamRect());
        event.stopPropagation();
    }
    onTouchCancel(event) {
        if (this.pendingAutoFullscreenTouchGesture) {
            this.pendingAutoFullscreenTouchGesture = false;
            event.preventDefault();
            event.stopPropagation();
            return;
        }
        this.pendingAutoFullscreenTouchGesture = false;
        this.onUserInteraction();
        event === null || event === void 0 ? void 0 : event.preventDefault();
        this.stream.getInput().onTouchCancel(event, this.getStreamRect());
        event.stopPropagation();
    }
    onTouchUpdate() {
        this.stream.getInput().onTouchUpdate(this.getStreamRect());
        this.updateKeyboardViewportVideoOffset();
        this.renderLocalTouchCursor();
        window.requestAnimationFrame(this.onTouchUpdate.bind(this));
    }
    onTouchMove(event) {
        if (this.pendingAutoFullscreenTouchGesture) {
            event.preventDefault();
            event.stopPropagation();
            return;
        }
        event.preventDefault();
        this.stream.getInput().onTouchMove(event, this.getStreamRect());
        event.stopPropagation();
    }
    // Gamepad
    onGamepadConnect(event) {
        this.onGamepadAdd(event.gamepad);
    }
    onGamepadAdd(gamepad) {
        this.stream.getInput().onGamepadConnect(gamepad);
    }
    onGamepadDisconnect(event) {
        this.stream.getInput().onGamepadDisconnect(event);
    }
    onGamepadUpdate() {
        this.stream.getInput().onGamepadUpdate();
        window.requestAnimationFrame(this.onGamepadUpdate.bind(this));
    }
    // Fullscreen
    promptAutoFullscreen() {
        return __awaiter(this, void 0, void 0, function* () {
            yield showModal(new AutoFullscreenModal(this.requestFullscreen.bind(this)));
        });
    }
    requestFullscreen() {
        return __awaiter(this, arguments, void 0, function* (showEscapeWarning = true) {
            var _a;
            const body = document.body;
            if (body) {
                if (!("requestFullscreen" in body && typeof body.requestFullscreen == "function")) {
                    yield showMessage(I.stream.fullscreenUnsupported);
                    return;
                }
                this.focusInput();
                yield this.requestPointerLock(false, true);
                if (!this.isFullscreen()) {
                    try {
                        yield body.requestFullscreen({
                            navigationUI: "hide"
                        });
                    }
                    catch (e) {
                        console.warn("failed to request fullscreen", e);
                    }
                }
                if (!this.isFullscreen()) {
                    yield this.exitPointerLock();
                    this.applyMouseLookConfig();
                }
                try {
                    if (screen && "orientation" in screen) {
                        const orientation = screen.orientation;
                        if ("lock" in orientation && typeof orientation.lock == "function") {
                            yield orientation.lock("landscape");
                        }
                    }
                }
                catch (e) {
                    console.warn("failed to set orientation to landscape", e);
                }
            }
            else {
                console.warn("root element not found");
            }
        });
    }
    exitFullscreen() {
        return __awaiter(this, void 0, void 0, function* () {
            yield this.exitPointerLock();
            this.applyMouseLookConfig();
            if ("keyboard" in navigator && navigator.keyboard && "unlock" in navigator.keyboard) {
                yield navigator.keyboard.unlock();
            }
            if ("exitFullscreen" in document && typeof document.exitFullscreen == "function") {
                yield document.exitFullscreen();
            }
        });
    }
    isFullscreen() {
        return "fullscreenElement" in document && !!document.fullscreenElement;
    }
    onFullscreenChange() {
        return __awaiter(this, void 0, void 0, function* () {
            if (this.isFullscreen()) {
                this.fullscreenOnNextInteractionArmed = false;
                this.pendingAutoFullscreenTouchGesture = false;
                this.pendingAutoFullscreenMouseGesture = false;
                this.manualFullscreenExitRequested = false;
            }
            else {
                const manualExit = this.manualFullscreenExitRequested;
                this.manualFullscreenExitRequested = false;
                yield this.exitPointerLock();
                if (this.autoEnterFullscreenOnStart && !manualExit) {
                    this.armFullscreenOnNextInteraction();
                }
            }
            this.checkFullyImmersed();
            this.sidebar.updateFullscreenButton();
            this.applyMouseLookConfig();
        });
    }
    markManualFullscreenExitRequested() {
        this.manualFullscreenExitRequested = true;
    }
    // Pointer Lock
    requestPointerLock() {
        return __awaiter(this, arguments, void 0, function* (errorIfNotFound = false, allowWithoutFullscreen = false) {
            if (!allowWithoutFullscreen && !this.isFullscreen()) {
                return;
            }
            if (document.pointerLockElement) {
                this.applyMouseLookConfig();
                return;
            }
            const inputElement = document.fullscreenElement
                || document.body
                || document.querySelector("video")
                || document.getElementById("input");
            if (inputElement && "requestPointerLock" in inputElement && typeof inputElement.requestPointerLock == "function") {
                this.focusInput();
                const onLockError = () => {
                    document.removeEventListener("pointerlockerror", onLockError);
                    inputElement.requestPointerLock();
                };
                document.addEventListener("pointerlockerror", onLockError, { once: true });
                try {
                    let promise = inputElement.requestPointerLock({
                        unadjustedMovement: true
                    });
                    if (promise) {
                        yield promise;
                    }
                    else {
                        inputElement.requestPointerLock();
                    }
                }
                catch (error) {
                    if (error instanceof Error && error.name == "NotSupportedError") {
                        try {
                            inputElement.requestPointerLock();
                        }
                        catch (retryError) {
                            console.warn("pointer lock retry failed", retryError);
                        }
                    }
                    else {
                        console.warn("pointer lock failed", error);
                    }
                }
                finally {
                    document.removeEventListener("pointerlockerror", onLockError);
                }
            }
            else if (errorIfNotFound) {
                yield showMessage(I.stream.pointerLockUnsupported);
            }
        });
    }
    exitPointerLock() {
        return __awaiter(this, void 0, void 0, function* () {
            if ("exitPointerLock" in document && typeof document.exitPointerLock == "function") {
                document.exitPointerLock();
            }
        });
    }
    onPointerLockChange() {
        this.checkFullyImmersed();
        this.applyMouseLookConfig();
    }
    // Windowed: keep the options bar. Fullscreen: hide it so clicks go to the remote screen.
    checkFullyImmersed() {
        setSidebarExtended(!this.isFullscreen());
        this.sidebar.updateFullscreenButton();
        requestAnimationFrame(() => this.syncToolbarLayout());
    }
    syncToolbarLayout() {
        var _a, _b;
        const fullscreen = this.isFullscreen();
        document.body.classList.toggle("stream-fullscreen", fullscreen);
        const bar = (_a = getSidebarRoot()) === null || _a === void 0 ? void 0 : _a.querySelector(".sidebar-background");
        const height = fullscreen ? 0 : Math.max(48, Math.ceil(((_b = bar === null || bar === void 0 ? void 0 : bar.getBoundingClientRect()) === null || _b === void 0 ? void 0 : _b.height) || 56));
        document.documentElement.style.setProperty("--stream-toolbar-height", `${height}px`);
        document.body.style.setProperty("--stream-toolbar-height", `${height}px`);
    }
    renderLocalTouchCursor() {
        const localCursorState = this.stream.getInput().getLocalCursorState();
        if (!(localCursorState === null || localCursorState === void 0 ? void 0 : localCursorState.visible)) {
            this.localTouchCursorDiv.hidden = true;
            return;
        }
        const rect = this.getStreamRect();
        if (rect.width <= 0 || rect.height <= 0) {
            this.localTouchCursorDiv.hidden = true;
            return;
        }
        this.localTouchCursorDiv.hidden = false;
        this.localTouchCursorDiv.style.left = `${rect.left + localCursorState.x * rect.width}px`;
        this.localTouchCursorDiv.style.top = `${rect.top + localCursorState.y * rect.height}px`;
    }
    onScreenKeyboardModeWillChange(event) {
        if (event.detail.enabled) {
            this.captureKeyboardViewportBaseline();
        }
    }
    captureKeyboardViewportBaseline() {
        var _a, _b;
        this.keyboardViewportBaselineHeight = (_b = (_a = window.visualViewport) === null || _a === void 0 ? void 0 : _a.height) !== null && _b !== void 0 ? _b : null;
        this.streamVideoTopOffsetPx = 0;
        this.applyStreamVideoTopOffset();
        this.updateKeyboardFloatingButtonPosition();
    }
    resetKeyboardViewportVideoOffset() {
        this.keyboardViewportBaselineHeight = null;
        this.streamVideoTopOffsetPx = 0;
        this.applyStreamVideoTopOffset();
        this.resetKeyboardFloatingButtonPosition();
    }
    updateKeyboardViewportVideoOffset() {
        this.updateKeyboardFloatingButtonPosition();
        const screenKeyboard = this.sidebar.getScreenKeyboard();
        const visualViewport = window.visualViewport;
        const baselineHeight = this.keyboardViewportBaselineHeight;
        const localCursorState = this.stream.getInput().getLocalCursorState();
        if (!screenKeyboard.isVisible() || !visualViewport || baselineHeight == null) {
            if (this.streamVideoTopOffsetPx != 0 && !screenKeyboard.isVisible()) {
                this.resetKeyboardViewportVideoOffset();
            }
            return;
        }
        const viewportShrink = baselineHeight - visualViewport.height;
        if (viewportShrink < 80) {
            if (this.streamVideoTopOffsetPx != 0) {
                this.streamVideoTopOffsetPx = 0;
                this.applyStreamVideoTopOffset();
            }
            return;
        }
        const streamRect = this.getStreamRect();
        if (streamRect.width <= 0 || streamRect.height <= 0) {
            return;
        }
        const visibleTop = visualViewport.offsetTop;
        const visibleBottom = visualViewport.offsetTop + visualViewport.height;
        let newTopOffsetPx = this.streamVideoTopOffsetPx;
        if (localCursorState.visible) {
            let delta = 0;
            const safeMargin = Math.min(100, visualViewport.height * 0.25);
            const cursorY = streamRect.top + localCursorState.y * streamRect.height;
            if (cursorY < visibleTop + safeMargin) {
                delta = visibleTop + safeMargin - cursorY;
            }
            else if (cursorY > visibleBottom - safeMargin) {
                delta = visibleBottom - safeMargin - cursorY;
            }
            newTopOffsetPx += delta;
        }
        else {
            const screenTopToVideoTop = visualViewport.height - streamRect.height;
            if (screenTopToVideoTop > 0) {
                newTopOffsetPx = visibleTop - screenTopToVideoTop;
            }
        }
        if (Math.abs(newTopOffsetPx - this.streamVideoTopOffsetPx) >= 1) {
            this.streamVideoTopOffsetPx = newTopOffsetPx;
            this.applyStreamVideoTopOffset();
        }
    }
    applyStreamVideoTopOffset() {
        if (Math.abs(this.streamVideoTopOffsetPx) < 0.5) {
            document.documentElement.style.removeProperty("--stream-video-top");
            return;
        }
        document.documentElement.style.setProperty("--stream-video-top", `calc(50% + ${this.streamVideoTopOffsetPx}px)`);
    }
    updateKeyboardFloatingButtonPosition() {
        const screenKeyboard = this.sidebar.getScreenKeyboard();
        const visualViewport = window.visualViewport;
        if (!screenKeyboard.isVisible() || !visualViewport) {
            this.resetKeyboardFloatingButtonPosition();
            return;
        }
        const bottomInset = Math.min(16, visualViewport.height * 0.08);
        const buttonTop = visualViewport.offsetTop + visualViewport.height - bottomInset;
        document.documentElement.style.setProperty("--stream-keyboard-button-top", `${buttonTop}px`);
    }
    resetKeyboardFloatingButtonPosition() {
        document.documentElement.style.removeProperty("--stream-keyboard-button-top");
    }
    mount(parent) {
        parent.appendChild(this.div);
    }
    unmount(parent) {
        parent.removeChild(this.div);
    }
    getStreamRect() {
        var _a, _b;
        // The bounding rect of the videoElement or canvasElement can be bigger than the actual video
        // -> We need to correct for this when sending positions, else positions are wrong
        return (_b = (_a = this.stream.getVideoRenderer()) === null || _a === void 0 ? void 0 : _a.getStreamRect()) !== null && _b !== void 0 ? _b : new DOMRect();
    }
    getStream() {
        return this.stream;
    }
}
class ConnectionInfoModal {
    constructor(onReconnect) {
        this.eventTarget = new EventTarget();
        this.root = document.createElement("div");
        this.textTy = null;
        this.text = document.createElement("p");
        this.options = document.createElement("div");
        this.debugDetailButton = document.createElement("button");
        this.reconnectButton = document.createElement("button");
        this.closeButton = document.createElement("button");
        this.debugDetail = ""; // We store this seperate because line breaks don't work when the element is not mounted on the dom
        this.debugDetailDisplay = document.createElement("div");
        this.onReconnect = onReconnect;
        this.root.classList.add("modal-video-connect");
        this.text.innerText = I.stream.connecting;
        this.root.appendChild(this.text);
        this.root.appendChild(this.options);
        this.options.classList.add("modal-video-connect-options");
        this.debugDetailButton.innerText = I.stream.showLogs;
        this.debugDetailButton.addEventListener("click", this.onDebugDetailClick.bind(this));
        this.options.appendChild(this.debugDetailButton);
        this.reconnectButton.innerText = "Reconnect";
        this.reconnectButton.title = "Refresh the stream without reloading this page";
        this.reconnectButton.addEventListener("click", () => {
            showModal(null);
            if (this.onReconnect) {
                this.onReconnect();
            }
        });
        this.options.appendChild(this.reconnectButton);
        this.closeButton.innerText = I.stream.close;
        this.closeButton.addEventListener("click", this.onClose.bind(this));
        this.options.appendChild(this.closeButton);
        this.debugDetailDisplay.classList.add("textlike");
        this.debugDetailDisplay.classList.add("modal-video-connect-debug");
    }
    onDebugDetailClick() {
        let debugDetailCurrentlyShown = this.root.contains(this.debugDetailDisplay);
        if (debugDetailCurrentlyShown) {
            this.debugDetailButton.innerText = I.stream.showLogs;
            this.root.removeChild(this.debugDetailDisplay);
        }
        else {
            this.debugDetailButton.innerText = I.stream.hideLogs;
            this.root.appendChild(this.debugDetailDisplay);
            this.debugDetailDisplay.innerText = this.debugDetail;
        }
    }
    debugLog(line) {
        this.debugDetail += `${line}\n`;
        this.debugDetailDisplay.innerText = this.debugDetail;
        console.info(`[Stream]: ${line}`);
    }
    onInfo(event) {
        var _a, _b, _c, _d, _e, _f, _g;
        const data = event.detail;
        if (data.type == "connectionComplete") {
            const text = I.stream.connectionComplete;
            this.text.innerText = text;
            this.debugLog(text);
        }
        else if (data.type == "videoReady") {
            this.eventTarget.dispatchEvent(new Event("ml-connected"));
        }
        else if (data.type == "addDebugLine") {
            const message = data.line.trim();
            if (message) {
                this.debugLog(message);
                if (!this.textTy) {
                    this.text.innerText = message;
                    this.textTy = (_b = (_a = data.additional) === null || _a === void 0 ? void 0 : _a.type) !== null && _b !== void 0 ? _b : null;
                }
                else if (((_c = data.additional) === null || _c === void 0 ? void 0 : _c.type) == "fatalDescription" || ((_d = data.additional) === null || _d === void 0 ? void 0 : _d.type) == "ifErrorDescription") {
                    if (this.text.innerText) {
                        this.text.innerText += "\n" + message;
                    }
                    else {
                        this.text.innerText = message;
                    }
                    this.textTy = data.additional.type;
                }
            }
            if (((_e = data.additional) === null || _e === void 0 ? void 0 : _e.type) == "fatal" || ((_f = data.additional) === null || _f === void 0 ? void 0 : _f.type) == "fatalDescription") {
                showModal(this);
            }
            else if (((_g = data.additional) === null || _g === void 0 ? void 0 : _g.type) == "informError") {
                showNotification(data.line);
            }
        }
        else if (data.type == "serverMessage") {
            const text = I.stream.serverMessage(data.message);
            this.text.innerText = text;
            this.debugLog(text);
        }
    }
    onClose() {
        showModal(null);
    }
    onFinish(abort) {
        return new Promise((resolve, reject) => {
            this.eventTarget.addEventListener("ml-connected", () => resolve(), { once: true, signal: abort });
        });
    }
    mount(parent) {
        parent.appendChild(this.root);
    }
    unmount(parent) {
        parent.removeChild(this.root);
    }
}
class AutoFullscreenModal {
    constructor(onConfirm) {
        this.message = document.createElement("p");
        this.root = document.createElement("div");
        this.okButton = document.createElement("button");
        this.cancelButton = document.createElement("button");
        this.onConfirm = onConfirm;
        this.message.innerText = I.stream.autoFullscreenPrompt;
        this.okButton.innerText = I.modal.ok;
        this.cancelButton.innerText = I.modal.cancel;
    }
    mount(parent) {
        this.root.appendChild(this.message);
        this.root.appendChild(this.okButton);
        this.root.appendChild(this.cancelButton);
        parent.appendChild(this.root);
    }
    unmount(parent) {
        parent.removeChild(this.root);
    }
    onFinish(abort) {
        return new Promise((resolve) => {
            this.okButton.addEventListener("click", () => __awaiter(this, void 0, void 0, function* () {
                yield this.onConfirm();
                resolve();
            }), { once: true, signal: abort });
            this.cancelButton.addEventListener("click", () => {
                resolve();
            }, { once: true, signal: abort });
        });
    }
}
class ViewerSidebar {
    constructor(app) {
        this.div = document.createElement("div");
        this.buttonDiv = document.createElement("div");
        this.screenKeyboard = new ScreenKeyboard();
        this.fullscreenButton = document.createElement("button");
        this.exitStreamButton = document.createElement("button");
        this.soundButton = document.createElement("button");
        this.reconnectButton = document.createElement("button");
        this.floatingSoundButton = document.createElement("button");
        this.gameMouseButton = document.createElement("button");
        this.floatingGameMouseButton = document.createElement("button");
        this.liveStats = document.createElement("span");
        this.maxFpsLabel = document.createElement("label");
        this.maxFpsSelect = document.createElement("select");
        this.modeButtons = new Map();
        this.app = app;
        this.div.classList.add("sidebar-stream");
        this.buttonDiv.classList.add("sidebar-stream-buttons");
        this.div.appendChild(this.buttonDiv);
        this.fullscreenButton.classList.add("stream-toolbar-fullscreen");
        this.fullscreenButton.addEventListener("click", () => __awaiter(this, void 0, void 0, function* () {
            if (this.app.isFullscreen()) {
                this.app.markManualFullscreenExitRequested();
                yield this.app.exitFullscreen();
            }
            else {
                yield this.app.requestFullscreen();
            }
        }));
        this.buttonDiv.appendChild(this.fullscreenButton);
        this.updateFullscreenButton();
        this.soundButton.classList.add("stream-sound-toggle");
        this.soundButton.addEventListener("click", () => {
            this.app.toggleSound();
        });
        this.buttonDiv.appendChild(this.soundButton);
        this.reconnectButton.classList.add("stream-reconnect");
        this.reconnectButton.addEventListener("click", () => {
            void this.app.reconnectStream();
        });
        this.buttonDiv.appendChild(this.reconnectButton);
        this.floatingSoundButton.classList.add("stream-sound-floating");
        this.floatingSoundButton.addEventListener("click", (event) => {
            event.preventDefault();
            event.stopPropagation();
            this.app.toggleSound();
        });
        stopPropagationOn(this.floatingSoundButton);
        this.floatingGameMouseButton.classList.add("stream-mouse-floating");
        this.floatingGameMouseButton.addEventListener("click", (event) => {
            event.preventDefault();
            event.stopPropagation();
            void this.app.captureFullscreenMouse();
        });
        stopPropagationOn(this.floatingGameMouseButton);
        for (const mode of VIEW_MODES) {
            const button = document.createElement("button");
            button.innerText = VIEW_MODE_LABELS[mode];
            button.title = VIEW_MODE_HINTS[mode];
            button.dataset.viewMode = mode;
            button.addEventListener("click", () => {
                void this.app.switchViewMode(mode);
            });
            this.buttonDiv.appendChild(button);
            this.modeButtons.set(mode, button);
        }
        this.maxFpsLabel.classList.add("stream-max-fps");
        this.maxFpsLabel.title = "Highest frame rate this computer will ask the host to send";
        const maxFpsText = document.createElement("span");
        maxFpsText.textContent = "Max FPS";
        this.maxFpsSelect.classList.add("stream-max-fps-select");
        this.maxFpsSelect.setAttribute("aria-label", "Max frame rate");
        for (const fps of MAX_FPS_OPTIONS) {
            const option = document.createElement("option");
            option.value = String(fps);
            option.textContent = String(fps);
            this.maxFpsSelect.appendChild(option);
        }
        this.maxFpsSelect.addEventListener("change", () => {
            const fps = Number.parseInt(this.maxFpsSelect.value, 10);
            void this.app.switchMaxFps(fps);
        });
        stopPropagationOn(this.maxFpsSelect);
        this.maxFpsLabel.append(maxFpsText, this.maxFpsSelect);
        this.buttonDiv.appendChild(this.maxFpsLabel);
        this.liveStats.classList.add("stream-live-stats");
        this.liveStats.textContent = "– FPS · – ms";
        this.buttonDiv.appendChild(this.liveStats);
        this.exitStreamButton.innerText = I.stream.exit;
        this.exitStreamButton.addEventListener("click", () => __awaiter(this, void 0, void 0, function* () {
            const stream = this.app.getStream();
            if (stream) {
                const success = yield stream.stop();
                if (!success) {
                    console.debug("Failed to close stream correctly");
                }
            }
            if (window.matchMedia('(display-mode: standalone)').matches) {
                history.back();
            }
            else {
                window.close();
            }
        }));
        this.buttonDiv.appendChild(this.exitStreamButton);
        this.updateModeButtons();
        this.updateSoundButton();
        this.updateReconnectButton();
        this.updateGameMouseButton();
        this.updateMaxFpsControl();
    }
    onCapabilitiesChange(_capabilities) {
    }
    getScreenKeyboard() {
        return this.screenKeyboard;
    }
    updateFullscreenButton() {
        const fullscreen = this.app.isFullscreen();
        this.fullscreenButton.innerText = fullscreen ? I.stream.exitFullscreen : I.stream.fullscreen;
        this.fullscreenButton.title = this.fullscreenButton.innerText;
        this.fullscreenButton.setAttribute("aria-pressed", fullscreen ? "true" : "false");
    }
    updateModeButtons() {
        const current = getViewMode();
        for (const [mode, button] of this.modeButtons) {
            const active = mode === current;
            button.classList.toggle("stream-mode-active", active);
            button.setAttribute("aria-pressed", active ? "true" : "false");
        }
    }
    updateMaxFpsControl() {
        this.maxFpsSelect.value = String(getMaxFps());
    }
    updateSoundButton() {
        const on = getSoundOn();
        const label = on ? "Sound On" : "Sound Off";
        this.soundButton.innerText = label;
        this.soundButton.title = "Turn sound on or off";
        this.soundButton.setAttribute("aria-pressed", on ? "true" : "false");
        this.soundButton.classList.toggle("stream-mode-active", on);
        this.floatingSoundButton.innerText = label;
        this.floatingSoundButton.title = "Turn sound on or off";
        this.floatingSoundButton.setAttribute("aria-pressed", on ? "true" : "false");
        this.floatingSoundButton.classList.toggle("stream-mode-active", on);
    }
    updateReconnectButton() {
        const busy = this.app.isReconnecting();
        this.reconnectButton.innerText = busy ? "Reconnecting…" : "Reconnect";
        this.reconnectButton.title = "Refresh the stream without reloading this page";
        this.reconnectButton.disabled = busy;
    }
    updateGameMouseButton() {
        const locked = this.app.isFullscreen() && !!document.pointerLockElement;
        this.floatingGameMouseButton.innerText = "Click to Look";
        this.floatingGameMouseButton.title = "Fullscreen keeps this computer's mouse still and sends look movement to the game. Click if the pointer was released.";
        this.floatingGameMouseButton.hidden = !this.app.isFullscreen() || locked;
        this.gameMouseButton.hidden = true;
    }
    updateLiveStats(stats) {
        const fpsValue = firstFiniteNumber(stats.video.playbackFps, stats.transport.measuredFps, stats.transport.webrtcFps);
        const ping = firstFiniteNumber(stats.transport.webrtcRttMs, stats.browserRtt);
        const fpsText = fpsValue == null ? "–" : String(Math.round(fpsValue));
        const pingText = ping == null ? "–" : `${Math.round(ping)} ms`;
        this.liveStats.textContent = `${fpsText} FPS · ${pingText}`;
        this.liveStats.title = "Measured decode FPS and network round-trip time from this computer";
    }
    extended() {
    }
    unextend() {
    }
    mount(parent) {
        parent.appendChild(this.div);
        document.body.appendChild(this.floatingSoundButton);
        document.body.appendChild(this.floatingGameMouseButton);
    }
    unmount(parent) {
        parent.removeChild(this.div);
        this.floatingSoundButton.remove();
        this.floatingGameMouseButton.remove();
    }
}
class SendKeycodeModal extends FormModal {
    constructor() {
        super();
        const keyList = [];
        for (const keyNameRaw in StreamKeys) {
            const keyName = keyNameRaw;
            const keyValue = StreamKeys[keyName];
            const PREFIX = "VK_";
            let name = keyName;
            if (name.startsWith(PREFIX)) {
                name = name.slice(PREFIX.length);
            }
            keyList.push({
                value: keyValue.toString(),
                name
            });
        }
        this.dropdownSearch = new SelectComponent("winKeycode", keyList, {
            hasSearch: true,
            displayName: I.stream.selectKeycode
        });
    }
    mountForm(form) {
        this.dropdownSearch.mount(form);
    }
    reset() {
        this.dropdownSearch.reset();
    }
    submit() {
        const keyString = this.dropdownSearch.getValue();
        if (keyString == null) {
            return null;
        }
        return parseInt(keyString);
    }
}
function firstFiniteNumber(...values) {
    for (const value of values) {
        const number = typeof value === "number" ? value : Number(value);
        if (Number.isFinite(number) && number >= 0) {
            return number;
        }
    }
    return null;
}
// Stop propagation so the stream doesn't get it
function stopPropagationOn(element) {
    element.addEventListener("keydown", onStopPropagation);
    element.addEventListener("keyup", onStopPropagation);
    element.addEventListener("keypress", onStopPropagation);
    element.addEventListener("click", onStopPropagation);
    element.addEventListener("mousedown", onStopPropagation);
    element.addEventListener("mouseup", onStopPropagation);
    element.addEventListener("mousemove", onStopPropagation);
    element.addEventListener("wheel", onStopPropagation);
    element.addEventListener("contextmenu", onStopPropagation);
    element.addEventListener("touchstart", onStopPropagation);
    element.addEventListener("touchmove", onStopPropagation);
    element.addEventListener("touchend", onStopPropagation);
    element.addEventListener("touchcancel", onStopPropagation);
}
function onStopPropagation(event) {
    event.stopPropagation();
}
