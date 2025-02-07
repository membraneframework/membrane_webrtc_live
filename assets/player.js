export function createPlayerHook(iceServers = [{ urls: "stun:stun.l.google.com:19302" }]) {
  return {
    async mounted() {
      // const videoPlayer = document.getElementById("videoPlayer");
      // videoPlayer.srcObject = new MediaStream();

      this.pc = new RTCPeerConnection({ iceServers: iceServers });

      this.pc.onicecandidate = (ev) => {
        message = JSON.stringify({ type: "ice_candidate", data: ev.candidate });
        this.pushEventTo(this.el, "webrtc_singaling", message);
      };

      // pc.ontrack = (event) => videoPlayer.srcObject.addTrack(event.track);

      // this.pc.ontrack = (ev) => {
      //   if (!this.el.srcObject) {
      //     this.el.srcObject = ev.streams[0];
      //   }
      // };

      // this.pc.addTransceiver("audio", { direction: "recvonly" });
      // this.pc.addTransceiver("video", { direction: "recvonly" });

      // const offer = await this.pc.createOffer();
      // await this.pc.setLocalDescription(offer);

      // const eventName = "answer" + "-" + this.el.id;
      // this.handleEvent(eventName, async (answer) => {
      //   await this.pc.setRemoteDescription(answer);
      // });

      // this.pushEventTo(this.el, "offer", offer);

      this.handleEvent("webrtc_singaling", async (event) => {
        const { type, data } = JSON.parse(event);

        switch (type) {
          case "sdp_offer":
            console.log("Received SDP offer:", data);
            await pc.setRemoteDescription(data);
            const answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);
            // ws.send(JSON.stringify({ type: "sdp_answer", data: answer }));
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

// const videoPlayer = document.getElementById("videoPlayer");
// const pcConfig = { iceServers: [{ urls: "stun:stun.l.google.com:19302" }] };
// const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
// const ws = new WebSocket(`${proto}//${window.location.hostname}:8829`);
// ws.onopen = () => start_connection(ws);
// ws.onclose = (event) => console.log("WebSocket connection was terminated:", event);

// const start_connection = async (ws) => {
//   videoPlayer.srcObject = new MediaStream();

//   const pc = new RTCPeerConnection(pcConfig);
//   pc.ontrack = (event) => videoPlayer.srcObject.addTrack(event.track);
//   pc.onicecandidate = (event) => {
//     if (event.candidate === null) return;

//     console.log("Sent ICE candidate:", event.candidate);
//     ws.send(JSON.stringify({ type: "ice_candidate", data: event.candidate }));
//   };

//   ws.onmessage = async (event) => {
//     const { type, data } = JSON.parse(event.data);

//     switch (type) {
//       case "sdp_offer":
//         console.log("Received SDP offer:", data);
//         await pc.setRemoteDescription(data);
//         const answer = await pc.createAnswer();
//         await pc.setLocalDescription(answer);
//         ws.send(JSON.stringify({ type: "sdp_answer", data: answer }));
//         console.log("Sent SDP answer:", answer);
//         break;
//       case "ice_candidate":
//         console.log("Recieved ICE candidate:", data);
//         await pc.addIceCandidate(data);
//     }
//   };
// };
