defmodule Membrane.WebRTC.Live.Utils do
  @moduledoc false

  defmacro log_prefix(id) do
    quote do
      [module: __MODULE__, id: unquote(id)]
      |> inspect()
    end
  end

  defmacro assing_struct(socket, id, struct) do
    quote do
      map =
        unquote(socket).assigns
        |> Map.get(__MODULE__, %{})
        |> Map.put(unquote(id), unquote(struct))

      unquote(socket)
      |> Phoenix.Socket.assign(__MODULE__, map)
    end
  end

  defmacro get_struct(socket, id) do
    quote do
      unquote(socket).assigns
      |> Map.get(__MODULE__)
      |> Map.get(unquote(id))
    end
  end
end
