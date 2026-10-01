defmodule HelloCloud.Application do
  @moduledoc """
  Starts Bandit on `$PORT` (3000 if unset).

  The listener binds the IPv6 wildcard rather than 0.0.0.0: Laravel Cloud's
  per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only network, and
  a Linux IPv6 wildcard socket is dual-stack by default, so one socket answers
  both. Nothing here sets `ipv6_v6only`.
  """
  use Application

  @impl true
  def start(_type, _args) do
    port = (System.get_env("PORT") || "3000") |> String.to_integer()

    children = [
      {Bandit,
       plug: HelloCloud.Router,
       scheme: :http,
       port: port,
       thousand_island_options: [transport_options: [:inet6, ip: {0, 0, 0, 0, 0, 0, 0, 0}]]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: HelloCloud.Supervisor)
  end
end
