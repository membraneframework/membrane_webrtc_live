export function createPlayerHook(iceServers = [{ urls: "stun:stun.l.google.com:19302" }]) {
  return {
    async mounted() {
      this.pc = new RTCPeerConnection({ iceServers: iceServers });

      // todo: get element by player id, different for every player
      pc.ontrack = (event) =>
        document.getElementById("videoPlayer").srcObject.addTrack(event.track);

      this.pc.onicecandidate = (ev) => {
        message = JSON.stringify({ type: "ice_candidate", data: ev.candidate });
        this.pushEventTo(this.el, "webrtc_singaling", message);
      };

      // todo: event name ("webrtc_signaling") should be suffixed with the component id
      this.handleEvent("webrtc_singaling", async (event) => {
        const { type, data } = JSON.parse(event);

        switch (type) {
          case "sdp_offer":
            console.log("Received SDP offer:", data);
            await pc.setRemoteDescription(data);

            const answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);

            message = JSON.stringify({ type: "sdp_answer", data: answer });
            this.pushEventTo(this.el, "webrtc_signaling", message);
            console.log("Sent SDP answer:", answer);

            break;
          case "ice_candidate":
            console.log("Recieved ICE candidate:", data);
            await pc.addIceCandidate(data);
        }
      });
    },
  };
}
