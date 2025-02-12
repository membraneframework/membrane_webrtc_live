function createPlayerHook(iceServers = [{ urls: "stun:stun.l.google.com:19302" }]) {
  return {
    async mounted() {
      console.log("MOUNTED");

      this.pc = new RTCPeerConnection({ iceServers: iceServers });
      this.el.srcObject = new MediaStream();

      this.pc.ontrack = (event) => {
        console.log("NEW TRACK", this.el);
        this.el.srcObject.addTrack(event.track);
      };

      this.pc.onicecandidate = (ev) => {
        console.log("NEW BROWSER ICE CANDIDATE");
        message = JSON.stringify({ type: "ice_candidate", data: ev.candidate });
        this.pushEventTo(this.el, "webrtc_signaling", message);
      };

      const eventName = "webrtc_signaling-" + this.el.id;
      this.handleEvent(eventName, async (event) => {
        console.log("NEW SIGNALING MESSAGE", event);

        const { type, data } = event;

        switch (type) {
          case "sdp_offer":
            console.log("Received SDP offer:", data);
            await this.pc.setRemoteDescription(data);

            const answer = await this.pc.createAnswer();
            await this.pc.setLocalDescription(answer);

            message = JSON.stringify({ type: "sdp_answer", data: answer });
            this.pushEventTo(this.el, "webrtc_signaling", message);
            console.log("Sent SDP answer:", answer);

            break;
          case "ice_candidate":
            console.log("Recieved ICE candidate:", data);
            await this.pc.addIceCandidate(data);
        }
      });
    },
  };
}
