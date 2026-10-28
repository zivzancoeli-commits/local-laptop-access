export const VIEW_MODES = ["gaming", "closed", "streaming", "battery", "sleep"];
export const VIEW_MODE_LABELS = {
    gaming: "Gaming",
    closed: "Closed",
    streaming: "Streaming",
    battery: "Battery",
    sleep: "Sleep",
};
export const VIEW_MODE_HINTS = {
    gaming: "1440×900 · 60 FPS · low latency",
    closed: "Lid shut: 720p · 30 FPS · cursor first · tight audio",
    streaming: "1440×900 · 60 FPS · high quality",
    battery: "720p · 30 FPS · lighter encode",
    sleep: "720p · 10 FPS · sound off",
};
const MODE_STORAGE_KEY = "mlViewMode";
const SOUND_STORAGE_KEY = "mlSoundOn";
const MAX_FPS_STORAGE_KEY = "mlMaxFps";
const GAME_MOUSE_STORAGE_KEY = "mlGameMouse";
export const MAX_FPS_OPTIONS = [120, 60, 45, 30, 24, 20, 15, 10];
export function getViewMode() {
    const raw = localStorage.getItem(MODE_STORAGE_KEY);
    if (raw === "closed" || raw === "streaming" || raw === "battery" || raw === "sleep" || raw === "gaming") {
        return raw;
    }
    return "gaming";
}
export function setViewMode(mode) {
    localStorage.setItem(MODE_STORAGE_KEY, mode);
    applyAudioBufferProfile(mode);
}
export function getSoundOn() {
    return localStorage.getItem(SOUND_STORAGE_KEY) === "1";
}
export function setSoundOn(on) {
    localStorage.setItem(SOUND_STORAGE_KEY, on ? "1" : "0");
    applySoundToPage(on);
}
export function getMaxFps() {
    const parsed = Number.parseInt(localStorage.getItem(MAX_FPS_STORAGE_KEY) ?? "", 10);
    if (MAX_FPS_OPTIONS.includes(parsed)) {
        return parsed;
    }
    return 60;
}
export function setMaxFps(fps) {
    const allowed = MAX_FPS_OPTIONS.includes(fps) ? fps : 60;
    localStorage.setItem(MAX_FPS_STORAGE_KEY, String(allowed));
}
export function getGameMouse() {
    return localStorage.getItem(GAME_MOUSE_STORAGE_KEY) === "1";
}
export function setGameMouse(on) {
    localStorage.setItem(GAME_MOUSE_STORAGE_KEY, on ? "1" : "0");
}
export function applySoundToPage(on) {
    window.__mlSoundOn = on;
    document.querySelectorAll("audio").forEach((el) => {
        el.muted = !on;
        el.volume = on ? 1 : 0;
        const stream = el.srcObject;
        if (stream instanceof MediaStream) {
            for (const track of stream.getAudioTracks()) {
                track.enabled = on;
            }
        }
        if (on) {
            void el.play().catch(() => { });
        }
        else {
            el.pause();
        }
    });
}
export function applyAudioBufferProfile(mode = getViewMode()) {
    if (mode === "streaming") {
        window.__mlAudioBuffer = { target: 0.12, max: 0.28 };
    }
    else if (mode === "battery") {
        window.__mlAudioBuffer = { target: 0.08, max: 0.18 };
    }
    else if (mode === "sleep") {
        window.__mlAudioBuffer = { target: 0.2, max: 0.4 };
    }
    else if (mode === "closed") {
        window.__mlAudioBuffer = { target: 0.02, max: 0.04 };
    }
    else {
        window.__mlAudioBuffer = { target: 0.02, max: 0.04 };
    }
}
export function applyViewModeSettings(settings, mode) {
    const next = Object.assign({}, settings);
    if (mode === "gaming") {
        next.videoSize = "custom";
        next.videoSizeCustom = { width: 1440, height: 900 };
        next.fps = 60;
        next.bitrate = 8000;
        next.videoFrameQueueSize = 1;
        next.audioSampleQueueSize = 2;
        next.playAudioLocal = false;
    }
    else if (mode === "closed") {
        next.videoSize = "720p";
        next.fps = 30;
        next.bitrate = 2500;
        next.videoFrameQueueSize = 1;
        next.audioSampleQueueSize = 1;
        next.playAudioLocal = false;
    }
    else if (mode === "streaming") {
        next.videoSize = "custom";
        next.videoSizeCustom = { width: 1440, height: 900 };
        next.fps = 60;
        next.bitrate = 14000;
        next.videoFrameQueueSize = 4;
        next.audioSampleQueueSize = 8;
        next.playAudioLocal = false;
    }
    else if (mode === "battery") {
        next.videoSize = "720p";
        next.fps = 30;
        next.bitrate = 4000;
        next.videoFrameQueueSize = 3;
        next.audioSampleQueueSize = 8;
        next.playAudioLocal = false;
    }
    else {
        next.videoSize = "720p";
        next.fps = 10;
        next.bitrate = 1200;
        next.videoFrameQueueSize = 8;
        next.audioSampleQueueSize = 2;
        next.playAudioLocal = false;
    }
    next.fps = Math.min(next.fps, getMaxFps());
    if (next.fps < 1) {
        next.fps = 1;
    }
    return next;
}
applyAudioBufferProfile(getViewMode());
applySoundToPage(getSoundOn() && getViewMode() !== "sleep");
