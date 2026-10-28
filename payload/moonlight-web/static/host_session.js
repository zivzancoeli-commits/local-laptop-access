import { apiGetApps, apiGetHost, apiGetHosts } from "./api.js";
import { buildUrl } from "./config_.js";
export function resolveHostSession(api) {
    return __awaiter(this, void 0, void 0, function* () {
        const hosts = yield apiGetHosts(api);
        const list = (hosts.response && hosts.response.hosts) ? hosts.response.hosts : [];
        const host = list.find((item) => item.paired === "Paired") || list[0];
        if (!host) {
            return null;
        }
        let currentGame = 0;
        try {
            const detailed = yield apiGetHost(api, { host_id: host.host_id });
            currentGame = detailed.current_game || 0;
        }
        catch (_a) {
        }
        const apps = yield apiGetApps(api, { host_id: host.host_id });
        if (!apps.length) {
            return null;
        }
        if (currentGame) {
            const running = apps.find((app) => app.app_id === currentGame);
            if (running) {
                return { hostId: host.host_id, appId: running.app_id };
            }
        }
        const desktop = apps.find((app) => app.title.toLowerCase() === "desktop") || apps[0];
        return { hostId: host.host_id, appId: desktop.app_id };
    });
}
export function streamUrlForSession(session) {
    const query = new URLSearchParams({
        hostId: String(session.hostId),
        appId: String(session.appId),
    });
    return buildUrl(`/stream.html?${query}`);
}
export function goToHostSession(api) {
    return __awaiter(this, void 0, void 0, function* () {
        try {
            const session = yield resolveHostSession(api);
            if (!session) {
                return false;
            }
            window.location.replace(streamUrlForSession(session));
            return true;
        }
        catch (_a) {
            return false;
        }
    });
}
function __awaiter(thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
}
