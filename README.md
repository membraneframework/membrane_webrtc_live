# Membrane WebRTC Live

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_webrtc_live.svg)](https://hex.pm/packages/membrane_webrtc_live)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_webrtc_live)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_webrtc_live.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_webrtc_live)

Phoenix LiveViews that can be used with Membrane Components from [membrane_webrtc_plugin](https://github.com/membraneframework/membrane_webrtc_plugin).

It's a part of the [Membrane Framework](https://membrane.stream).

## Installation

The package can be installed by adding `membrane_webrtc_live` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_webrtc_live, "~> 0.1.0"}
  ]
end
```

## Modules

`Membrane.WebRTC.Live` comes with two `Phoenix.LiveView`s: 
 - `Membrane.WebRTC.Live.Capture` - exchanges WebRTC signaling messages between `Membrane.WebRTC.Source` and the browser. It expects the same `Membrane.WebRTC.SignalingChannel` that has been passed to the related `Membrane.WebRTC.Source`. As a result, `Membrane.Webrtc.Source` will return the media stream captured from the browser, where `Membrane.WebRTC.Live.Capture` has been rendered.
 - `Membrane.WebRTC.Live.Player` - exchanges WebRTC signaling messages between `Membrane.WebRTC.Sink` and the browser. It expects the same `Membrane.WebRTC.SignalingChannel` that has been passed to the related `Membrane.WebRTC.Sink`. As a result, `Membrane.WebRTC.Live.Player` will play media streams passed to the related `Membrane.WebRTC.Sink`. Currently supports up to one video stream and up to one audio stream.

## Usage 

To use `Phoenix.LiveView`s from this repository, you have to use related JS hooks. To do so, add the following code snippet to `assets/js/app.js`

```js
import { createCaptureHook, createPlayerHook } from "membrane_webrtc_live";

let Hooks = {};
const iceServers = [{ urls: "stun:stun.l.google.com:19302" }];
Hooks.Capture = createCaptureHook(iceServers);
Hooks.Player = createPlayerHook(iceServers);
```

and add `Hooks` to the WebSocket constructor. It can be done in a following way:

```js
new LiveSocket("/live", Socket, {
  params: SomeParams,
  hooks: Hooks,
});
```

To see full usage example, take a look at `example_project/` directory in this repository (take a look especially at `example_project/assets/js/app.js` and `example_project/lib/example_project_web/live_views/echo.ex`).

## Copyright and License

Copyright 2025, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_webrtc_live)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_webrtc_live)

Licensed under the [Apache License, Version 2.0](LICENSE)
