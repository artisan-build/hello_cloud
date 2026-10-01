defmodule HelloCloud.MixProject do
  use Mix.Project

  # build_path and deps_path are pushed under target/ because main's .gitignore
  # already ignores /target/ -- that keeps `git status` clean on this branch
  # without touching a shared file.
  def project do
    [
      app: :hello_cloud,
      version: "1.0.0",
      elixir: "~> 1.18",
      build_path: "target/_build",
      deps_path: "target/deps",
      start_permanent: true,
      deps: deps(),
      releases: releases()
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {HelloCloud.Application, []}]
  end

  defp deps do
    [
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.5"}
    ]
  end

  # include_erts: true is the whole point -- the release carries its own ERTS,
  # so the artifact needs nothing installed on the host that runs it.
  defp releases do
    [
      hello_cloud: [
        include_erts: true,
        include_executables_for: [:unix],
        strip_beams: true,
        quiet: true
      ]
    ]
  end
end
