defmodule BlurHash.MixProject do
  use Mix.Project

  def project do
    [
      app: :blurhash,
      version: "1.0.0",
      elixir: "~> 1.7",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      name: "BlurHash",
      source_url: "https://github.com/perzanko/blurhash-elixir"
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:ex_doc, "~> 0.22", only: :dev, runtime: false}
    ]
  end

  defp description() do
    """
    Pure Elixir implementation of Blurhash algorithm with no additional dependencies. Blurhash is an algorithm by Dag Ågren of Wolt that decodes an image to a very compact (~ 20-30 bytes) ASCII string representation, which can be then decoded into a blurred placeholder image.
    """
  end

  defp package() do
    [
      name: "blurhash",
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*
                CHANGELOG*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/perzanko/blurhash-elixir"
      }
    ]
  end
end
