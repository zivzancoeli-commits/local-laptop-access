var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
import { TransportChannelId } from "../../api_bindings.js";
import { CAPABILITIES_CODECS, emptyVideoCodecs, maybeVideoCodecs } from "../video.js";
export class WebRTCTransport {
    constructor(logger) {
        this.implementationName = "webrtc";
        this.peer = null;
        this.onsendmessage = null;
        this.remoteDescription = null;
        this.iceCandidates = [];
        this.wasConnected = false;
        this.channels = [];
        this.videoTrackHolder = { ontrack: null, track: null };
        this.videoReceiver = null;
        this.lastInboundSample = null;
        this.audioTrackHolder = { ontrack: null, track: null };
        this.onconnect = null;
        this.onclose = null;
        this.logger = logger !== null && logger !== void 0 ? logger : null;
    }
    initPeer(configuration) {
        return __awaiter(this, void 0, void 0, function* () {
            var _a, _b;
            (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug(`Creating Client Peer`);
            if (this.peer) {
                (_b = this.logger) === null || _b === void 0 ? void 0 : _b.debug(`Cannot create Peer because a Peer already exists`);
                return;
            }
            // Configure web rtc
            // TODO: use this for signaling instead and extend the protocol so that the client also requests a control channel with name: "control", protocol:"moonlight-control-v1": https://www.ietf.org/archive/id/draft-ietf-wish-whep-02.html
            this.peer = new RTCPeerConnection(configuration);
            this.peer.addEventListener("error", this.onError.bind(this));
            this.peer.addEventListener("icecandidate", this.onIceCandidate.bind(this));
            this.peer.addEventListener("connectionstatechange", this.onConnectionStateChange.bind(this));
            this.peer.addEventListener("signalingstatechange", this.onSignalingStateChange.bind(this));
            this.peer.addEventListener("iceconnectionstatechange", this.onIceConnectionStateChange.bind(this));
            this.peer.addEventListener("icegatheringstatechange", this.onIceGatheringStateChange.bind(this));
            this.peer.addEventListener("track", this.onTrack.bind(this));
            this.peer.addEventListener("datachannel", this.onDataChannel.bind(this));
            this.initChannels();
            // Maybe we already received data
            if (this.remoteDescription) {
                yield this.handleRemoteDescription(this.remoteDescription);
            }
            yield this.tryDequeueIceCandidates();
        });
    }
    onError(event) {
        var _a;
        (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug(`Web Socket or WebRtcPeer Error`);
        console.error(`Web Socket or WebRtcPeer Error`, event);
    }
    sendMessage(message) {
        var _a;
        if (this.onsendmessage) {
            this.onsendmessage(message);
        }
        else {
            (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug("Failed to call onicecandidate because no handler is set");
        }
    }
    onReceiveMessage(message) {
        return __awaiter(this, void 0, void 0, function* () {
            if ("Description" in message) {
                const description = message.Description;
                yield this.handleRemoteDescription({
                    type: description.ty,
                    sdp: description.sdp
                });
            }
            else if ("AddIceCandidate" in message) {
                const candidate = message.AddIceCandidate;
                yield this.addIceCandidate({
                    candidate: candidate.candidate,
                    sdpMid: candidate.sdp_mid,
                    sdpMLineIndex: candidate.sdp_mline_index,
                    usernameFragment: candidate.username_fragment
                });
            }
        });
    }
    handleRemoteDescription(sdp) {
        return __awaiter(this, void 0, void 0, function* () {
            var _a, _b, _c, _d;
            (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug(`Received remote description: ${sdp === null || sdp === void 0 ? void 0 : sdp.type}`);
            const remoteDescription = sdp;
            this.remoteDescription = remoteDescription;
            if (!this.peer) {
                return;
            }
            this.remoteDescription = null;
            if (remoteDescription) {
                yield this.peer.setRemoteDescription(remoteDescription);
                if (remoteDescription.type == "offer") {
                    yield this.peer.setLocalDescription();
                    const localDescription = this.peer.localDescription;
                    if (!localDescription) {
                        (_b = this.logger) === null || _b === void 0 ? void 0 : _b.debug("Peer didn't have a localDescription whilst receiving an offer and trying to answer");
                        return;
                    }
                    (_c = this.logger) === null || _c === void 0 ? void 0 : _c.debug(`Responding to offer description: ${localDescription.type}`);
                    this.sendMessage({
                        Description: {
                            ty: localDescription.type,
                            sdp: (_d = localDescription.sdp) !== null && _d !== void 0 ? _d : ""
                        }
                    });
                }
            }
        });
    }
    onIceCandidate(event) {
        var _a, _b, _c, _d, _e, _f;
        if (event.candidate) {
            const candidate = event.candidate.toJSON();
            (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug(`Sending ice candidate: ${candidate.candidate}`);
            this.sendMessage({
                AddIceCandidate: {
                    candidate: (_b = candidate.candidate) !== null && _b !== void 0 ? _b : "",
                    sdp_mid: (_c = candidate.sdpMid) !== null && _c !== void 0 ? _c : null,
                    sdp_mline_index: (_d = candidate.sdpMLineIndex) !== null && _d !== void 0 ? _d : null,
                    username_fragment: (_e = candidate.usernameFragment) !== null && _e !== void 0 ? _e : null
                }
            });
        }
        else {
            (_f = this.logger) === null || _f === void 0 ? void 0 : _f.debug("No new ice candidates");
        }
    }
    addIceCandidate(candidate) {
        return __awaiter(this, void 0, void 0, function* () {
            var _a, _b;
            (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug(`Received ice candidate: ${candidate.candidate}`);
            if (!this.peer) {
                (_b = this.logger) === null || _b === void 0 ? void 0 : _b.debug("Buffering ice candidate");
                this.iceCandidates.push(candidate);
                return;
            }
            yield this.tryDequeueIceCandidates();
            yield this.peer.addIceCandidate(candidate);
        });
    }
    tryDequeueIceCandidates() {
        return __awaiter(this, void 0, void 0, function* () {
            var _a;
            if (!this.peer) {
                (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug("called tryDequeueIceCandidates without a peer");
                return;
            }
            for (const candidate of this.iceCandidates) {
                yield this.peer.addIceCandidate(candidate);
            }
            this.iceCandidates.length = 0;
        });
    }
    onConnectionStateChange() {
        var _a, _b;
        if (!this.peer) {
            (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug("OnConnectionStateChange without a peer");
            return;
        }
        let type = null;
        if (this.peer.connectionState == "connected") {
            type = "recover";
            if (this.onconnect) {
                this.onconnect();
            }
            this.wasConnected = true;
        }
        else if ((this.peer.connectionState == "failed" || this.peer.connectionState == "closed") && this.peer.iceGatheringState == "complete") {
            type = "fatal";
        }
        if (this.peer.connectionState == "failed" || this.peer.connectionState == "closed") {
            if (this.onclose) {
                if (this.wasConnected) {
                    this.onclose("failed");
                }
                else {
                    this.onclose("failednoconnect");
                }
            }
        }
        (_b = this.logger) === null || _b === void 0 ? void 0 : _b.debug(`Changing Peer State to ${this.peer.connectionState}`, {
            type: type !== null && type !== void 0 ? type : undefined
        });
    }
    onSignalingStateChange() {
        var _a, _b;
        if (!this.peer) {
            (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug("OnSignalingStateChange without a peer");
            return;
        }
        (_b = this.logger) === null || _b === void 0 ? void 0 : _b.debug(`Changing Peer Signaling State to ${this.peer.signalingState}`);
    }
    onIceConnectionStateChange() {
        var _a, _b;
        if (!this.peer) {
            (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug("OnIceConnectionStateChange without a peer");
            return;
        }
        (_b = this.logger) === null || _b === void 0 ? void 0 : _b.debug(`Changing Peer Ice State to ${this.peer.iceConnectionState}`);
    }
    onIceGatheringStateChange() {
        var _a, _b;
        if (!this.peer) {
            (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug("OnIceGatheringStateChange without a peer");
            return;
        }
        (_b = this.logger) === null || _b === void 0 ? void 0 : _b.debug(`Changing Peer Ice Gathering State to ${this.peer.iceGatheringState}`);
        if (this.peer.iceConnectionState == "new" && this.peer.iceGatheringState == "complete") {
            // we failed without connection
            if (this.onclose) {
                this.onclose("failednoconnect");
            }
        }
    }
    initChannels() {
        var _a, _b;
        if (!this.peer) {
            (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug("Failed to initialize channel without peer");
            return;
        }
        if (this.channels.length > 0) {
            (_b = this.logger) === null || _b === void 0 ? void 0 : _b.debug("Already initialized channels");
            return;
        }
        for (const channelRaw in TransportChannelId) {
            const channel = channelRaw;
            if (channel == "HOST_VIDEO") {
                const channel = new WebRTCInboundTrackTransportChannel(this.logger, "videotrack", "video", this.videoTrackHolder);
                this.channels[TransportChannelId.HOST_VIDEO] = channel;
                continue;
            }
            if (channel == "HOST_AUDIO") {
                const channel = new WebRTCInboundTrackTransportChannel(this.logger, "audiotrack", "audio", this.audioTrackHolder);
                this.channels[TransportChannelId.HOST_AUDIO] = channel;
                continue;
            }
            // All Data Channels are created by the server
            const id = TransportChannelId[channel];
            this.channels[id] = new WebRTCDataTransportChannel(channel, null);
        }
    }
    onTrack(event) {
        var _a;
        const track = event.track;
        const receiver = event.receiver;
        if (track.kind == "video") {
            this.videoReceiver = receiver;
        }
        receiver.jitterBufferTarget = 0;
        if ("playoutDelayHint" in receiver) {
            receiver.playoutDelayHint = 0;
        }
        if (typeof receiver.jitterBufferMinimumDelay === "number") {
            receiver.jitterBufferMinimumDelay = 0;
        }
        (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug(`Adding receiver: ${track.kind}, ${track.id}, ${track.label}`);
        if (track.kind == "video") {
            if ("contentHint" in track) {
                track.contentHint = "motion";
            }
            this.videoTrackHolder.track = track;
            if (!this.videoTrackHolder.ontrack) {
                throw "No video track listener registered!";
            }
            this.videoTrackHolder.ontrack();
        }
        else if (track.kind == "audio") {
            track.enabled = !!window.__mlSoundOn;
            this.audioTrackHolder.track = track;
            if (!this.audioTrackHolder.ontrack) {
                throw "No audio track listener registered!";
            }
            this.audioTrackHolder.ontrack();
        }
    }
    // Handle data channels created by the remote peer (server)
    onDataChannel(event) {
        var _a, _b, _c, _d;
        const remoteChannel = event.channel;
        const label = remoteChannel.label;
        (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug(`Received remote data channel: ${label}`);
        // Map the channel label to the corresponding TransportChannelId
        const channelKey = label.toUpperCase();
        if (channelKey in TransportChannelId) {
            const id = TransportChannelId[channelKey];
            const existingChannel = this.channels[id];
            // If we already have a channel for this ID, replace its underlying RTCDataChannel
            // with the remote one so we can receive messages from the server
            if (existingChannel && existingChannel.type === "data") {
                (_b = this.logger) === null || _b === void 0 ? void 0 : _b.debug(`Replacing underlying channel for ${label} with remote channel`);
                existingChannel.replaceChannel(remoteChannel);
            }
            else {
                (_c = this.logger) === null || _c === void 0 ? void 0 : _c.debug(`Creating new channel for ${label}`);
                this.channels[id] = new WebRTCDataTransportChannel(label, remoteChannel);
            }
        }
        else {
            (_d = this.logger) === null || _d === void 0 ? void 0 : _d.debug(`Unknown remote data channel: ${label}`);
        }
    }
    setupHostVideo(_setup) {
        return __awaiter(this, void 0, void 0, function* () {
            // TODO: check transport type
            var _a;
            let capabilities;
            if ("getCapabilities" in RTCRtpReceiver && (capabilities = RTCRtpReceiver.getCapabilities("video"))) {
                const codecs = emptyVideoCodecs();
                for (const codec in codecs) {
                    const supportRequirements = CAPABILITIES_CODECS[codec];
                    if (!supportRequirements) {
                        continue;
                    }
                    let supported = false;
                    capabilityCodecLoop: for (const codecCapability of capabilities.codecs) {
                        if (codecCapability.mimeType != supportRequirements.mimeType) {
                            continue;
                        }
                        for (const fmtpLine of supportRequirements.fmtpLine) {
                            if (!((_a = codecCapability.sdpFmtpLine) === null || _a === void 0 ? void 0 : _a.includes(fmtpLine))) {
                                continue capabilityCodecLoop;
                            }
                        }
                        supported = true;
                        break;
                    }
                    codecs[codec] = supported;
                }
                return codecs;
            }
            else {
                return maybeVideoCodecs();
            }
        });
    }
    setupHostAudio(_setup) {
        return __awaiter(this, void 0, void 0, function* () {
            // TODO: check transport type
        });
    }
    getChannel(id) {
        var _a;
        const channel = this.channels[id];
        if (!channel) {
            (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug("Failed to setup video without peer");
            throw `Failed to get channel because it is not yet initialized, Id: ${id}`;
        }
        return channel;
    }
    setRemoteAudioEnabled(on) {
        if (this.audioTrackHolder.track) {
            this.audioTrackHolder.track.enabled = on;
        }
        if (!this.peer) {
            return;
        }
        for (const transceiver of this.peer.getTransceivers()) {
            const receiverTrack = transceiver.receiver && transceiver.receiver.track;
            const senderTrack = transceiver.sender && transceiver.sender.track;
            const kind = (receiverTrack && receiverTrack.kind) || (senderTrack && senderTrack.kind);
            if (kind !== "audio") {
                continue;
            }
            try {
                transceiver.direction = on ? "recvonly" : "inactive";
            }
            catch (_err) {
            }
        }
    }
    close() {
        return __awaiter(this, void 0, void 0, function* () {
            var _a, _b;
            (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug("Closing WebRTC Peer");
            (_b = this.peer) === null || _b === void 0 ? void 0 : _b.close();
        });
    }
    getStats() {
        return __awaiter(this, void 0, void 0, function* () {
            const statsData = {};
            if (!this.peer) {
                return statsData;
            }
            const stats = yield this.peer.getStats();
            if (this.videoReceiver) {
                try {
                    this.videoReceiver.jitterBufferTarget = 0;
                }
                catch (_a) { }
                if ("playoutDelayHint" in this.videoReceiver) {
                    this.videoReceiver.playoutDelayHint = 0;
                }
            }
            let framesDecoded = null;
            let framesPerSecond = null;
            let roundTripTimeSec = null;
            for (const value of stats.values()) {
                const type = value.type;
                if (type === "inbound-rtp" && (value.kind === "video" || value.mediaType === "video")) {
                    if (typeof value.decoderImplementation === "string") {
                        statsData.decoderImplementation = value.decoderImplementation;
                    }
                    if (typeof value.frameWidth === "number") {
                        statsData.videoWidth = value.frameWidth;
                    }
                    if (typeof value.frameHeight === "number") {
                        statsData.videoHeight = value.frameHeight;
                    }
                    if (typeof value.framesPerSecond === "number") {
                        framesPerSecond = value.framesPerSecond;
                        statsData.webrtcFps = value.framesPerSecond;
                    }
                    if (typeof value.framesDecoded === "number") {
                        framesDecoded = value.framesDecoded;
                        statsData.webrtcFramesDecoded = value.framesDecoded;
                    }
                    if (typeof value.framesReceived === "number") {
                        statsData.webrtcFramesReceived = value.framesReceived;
                    }
                    if (typeof value.packetsReceived === "number") {
                        statsData.webrtcPacketsReceived = value.packetsReceived;
                    }
                    if (typeof value.packetsLost === "number") {
                        statsData.webrtcPacketsLost = value.packetsLost;
                    }
                    if (typeof value.framesDropped === "number") {
                        statsData.webrtcFramesDropped = value.framesDropped;
                    }
                    if (typeof value.jitter === "number") {
                        statsData.webrtcJitterMs = value.jitter * 1000;
                    }
                }
                if (type === "candidate-pair") {
                    const nominated = value.nominated === true || value.selected === true;
                    const succeeded = value.state === "succeeded" || value.state === "in-progress";
                    if (nominated && succeeded && typeof value.currentRoundTripTime === "number") {
                        roundTripTimeSec = value.currentRoundTripTime;
                    }
                    else if (roundTripTimeSec == null && typeof value.currentRoundTripTime === "number" && value.state === "succeeded") {
                        roundTripTimeSec = value.currentRoundTripTime;
                    }
                }
                if (type === "remote-inbound-rtp" && roundTripTimeSec == null && typeof value.roundTripTime === "number") {
                    roundTripTimeSec = value.roundTripTime;
                }
            }
            const now = performance.now();
            if (framesDecoded != null) {
                const previous = this.lastInboundSample;
                if (previous && now > previous.time) {
                    const deltaSeconds = (now - previous.time) / 1000;
                    const deltaFrames = framesDecoded - previous.frames;
                    if (deltaSeconds >= 0.2 && deltaFrames >= 0) {
                        statsData.measuredFps = deltaFrames / deltaSeconds;
                    }
                }
                this.lastInboundSample = { time: now, frames: framesDecoded };
            }
            if (framesPerSecond != null && statsData.measuredFps == null) {
                statsData.measuredFps = framesPerSecond;
            }
            if (roundTripTimeSec != null) {
                statsData.webrtcRttMs = roundTripTimeSec * 1000;
            }
            return statsData;
        });
    }
}
// This receives track data
class WebRTCInboundTrackTransportChannel {
    constructor(logger, type, label, trackHolder) {
        this.canReceive = true;
        this.canSend = false;
        this.trackListeners = [];
        this.logger = logger;
        this.type = type;
        this.label = label;
        this.trackHolder = trackHolder;
        this.trackHolder.ontrack = this.onTrack.bind(this);
    }
    setTrack(_track) {
        throw "WebRTCInboundTrackTransportChannel cannot addTrack";
    }
    onTrack() {
        var _a;
        const track = this.trackHolder.track;
        if (!track) {
            (_a = this.logger) === null || _a === void 0 ? void 0 : _a.debug("WebRTC TrackHolder.track is null!");
            return;
        }
        for (const listener of this.trackListeners) {
            listener(track);
        }
    }
    addTrackListener(listener) {
        if (this.trackHolder.track) {
            listener(this.trackHolder.track);
        }
        this.trackListeners.push(listener);
    }
    removeTrackListener(listener) {
        const index = this.trackListeners.indexOf(listener);
        if (index != -1) {
            this.trackListeners.splice(index, 1);
        }
    }
}
class WebRTCDataTransportChannel {
    constructor(label, channel, logger) {
        var _a;
        this.type = "data";
        this.canReceive = true;
        this.canSend = true;
        this.logger = null;
        this.sendQueue = [];
        this.receiveListeners = [];
        this.label = label;
        this.channel = channel;
        this.boundOnMessage = this.onMessage.bind(this);
        this.boundTryDequeueSendQueue = this.tryDequeueSendQueue.bind(this);
        this.logger = logger !== null && logger !== void 0 ? logger : null;
        (_a = this.channel) === null || _a === void 0 ? void 0 : _a.addEventListener("message", this.boundOnMessage);
    }
    // Replace the underlying channel with a new one (e.g., from remote peer)
    // This is used when we receive a data channel from the server that should
    // replace our locally created one for receiving messages
    replaceChannel(newChannel) {
        var _a, _b, _c;
        // Remove listener from old channel
        (_a = this.channel) === null || _a === void 0 ? void 0 : _a.removeEventListener("open", this.boundTryDequeueSendQueue);
        (_b = this.channel) === null || _b === void 0 ? void 0 : _b.removeEventListener("bufferedamountlow", this.boundTryDequeueSendQueue);
        (_c = this.channel) === null || _c === void 0 ? void 0 : _c.removeEventListener("message", this.boundOnMessage);
        // Add listener to new channel
        this.channel = newChannel;
        try {
            this.channel.bufferedAmountLowThreshold = 1024;
        }
        catch (_d) { }
        this.channel.addEventListener("open", this.boundTryDequeueSendQueue);
        this.channel.addEventListener("bufferedamountlow", this.boundTryDequeueSendQueue);
        this.channel.addEventListener("message", this.boundOnMessage);
    }
    isLatestOnly() {
        return this.label === "mouse_absolute" || this.label === "mouse_relative";
    }
    send(message) {
        const latest = this.isLatestOnly();
        if (!this.channel || this.channel.readyState != "open") {
            const copy = message.slice(0);
            this.sendQueue = latest ? [copy] : this.sendQueue.concat([copy]);
            if (!latest && this.sendQueue.length > 64) {
                this.sendQueue.shift();
            }
            return;
        }
        if (latest) {
            if (this.channel.bufferedAmount > 2048) {
                this.sendQueue = [message.slice(0)];
                return;
            }
            this.sendQueue.length = 0;
            this.channel.send(message);
            return;
        }
        this.channel.send(message);
    }
    tryDequeueSendQueue() {
        if (!this.channel || this.channel.readyState != "open") {
            return;
        }
        for (const message of this.sendQueue.splice(0)) {
            this.channel.send(message);
        }
    }
    onMessage(event) {
        const data = event.data;
        if (!(data instanceof ArrayBuffer)) {
            console.warn(`received text data on webrtc channel ${this.label}`);
            return;
        }
        for (const listener of this.receiveListeners) {
            listener(event.data);
        }
    }
    addReceiveListener(listener) {
        this.receiveListeners.push(listener);
    }
    removeReceiveListener(listener) {
        const index = this.receiveListeners.indexOf(listener);
        if (index != -1) {
            this.receiveListeners.splice(index, 1);
        }
    }
    estimatedBufferedBytes() {
        var _a, _b;
        return (_b = (_a = this.channel) === null || _a === void 0 ? void 0 : _a.bufferedAmount) !== null && _b !== void 0 ? _b : null;
    }
}
