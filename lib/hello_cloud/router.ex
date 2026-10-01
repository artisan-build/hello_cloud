defmodule HelloCloud.Router do
  @moduledoc """
  Two routes: the shared page and the OG card.

  Both the template and the PNG are read at COMPILE time into module
  attributes, so they live inside the .beam files that ship in the release.
  Laravel Cloud's filesystem is ephemeral and nothing in this repo is on it.
  """
  use Plug.Router

  @language "Elixir"
  @branch "elixir"
  @repo_url "https://github.com/artisan-build/hello_cloud"

  @external_resource "shared/page.html"
  @external_resource "shared/index-url.txt"
  @external_resource "og.png"

  @template File.read!("shared/page.html")
  @index_url File.read!("shared/index-url.txt") |> String.trim()
  @og_png File.read!("og.png")

  plug :match
  plug :dispatch

  get "/" do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, render(host(conn)))
  end

  get "/og.png" do
    conn
    |> put_resp_content_type("image/png", nil)
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, @og_png)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  # The absolute URLs come from the request's Host header with the scheme
  # hard-coded to https: Cloud terminates TLS upstream and then sends
  # X-Forwarded-Proto: http on an https request, so that header is unusable.
  defp host(conn) do
    case get_req_header(conn, "host") do
      [h | _] -> h
      [] -> "#{conn.host}:#{conn.port}"
    end
  end

  # Fills the shared template's seven placeholders. Keep in step with main.go.
  defp render(host) do
    base = "https://" <> host

    @template
    |> String.replace("{{LANGUAGE}}", @language)
    |> String.replace("{{BRANCH}}", @branch)
    |> String.replace("{{BRANCH_URL}}", @repo_url <> "/tree/" <> @branch)
    |> String.replace("{{OG_IMAGE}}", base <> "/og.png")
    |> String.replace("{{PAGE_URL}}", base <> "/")
    |> String.replace("{{INDEX_URL}}", @index_url)
    |> String.replace("{{EXTRA}}", "")
  end
end
