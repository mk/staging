defmodule Staging.Mixfile do
  use Mix.Project

  def project do
    [app: :staging,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:gen_stage, :logger]]
  end

  # Type "mix help deps" for more examples and options
  defp deps do
    [{:gen_stage, "~> 0.6.1"}]
  end
end
