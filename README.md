# BlurHash

Pure Elixir implementation of Blurhash algorithm with no additional dependencies.

Blurhash is an algorithm by Dag Ågren of Wolt that decodes an image to a very compact (~ 20-30 bytes) ASCII string representation, which can be then decoded into a blurred placeholder image. See the main [repository](https://github.com/woltapp/blurhash) for the rationale and details.

More details on https://blurha.sh/

Documentation available on hexdocs: https://hexdocs.pm/blurhash

## Installation

BlurHash is published on [Hex](https://hexdocs.pm/blurhash). Add it to your list of dependencies in mix.exs:

```elixir
def deps do
  [
    {:blurhash, "~> 2.0.0"}
  ]
end
```

## Usage

```elixir
# Pixel data supplied in RGB order, with 3 bytes per pixels.
pixels = [255, 43, 20, 11, 0, 155, ...]

hash = BlurHash.encode(pixels, 30, 30, 4, 3)

IO.inspect(hash) # "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
```

If you would like to convert raw binary instead of RGB image format, you can use eg [Mogrify](https://github.com/route/mogrify) package to perform conversion.

```elixir
import Mogrify

file =
  open(path)
  |> format("rgb")
  |> save()

pixels =
  File.read!(file.path)
  |> :binary.bin_to_list()

hash = BlurHash.encode(pixels, 30, 30, 4, 3)

IO.inspect(hash) # "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
```

<!-- CONTRIBUTING -->
## Contributing

Any contributions you make are **greatly appreciated** 🤓.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

<!-- LICENSE -->
## License

Distributed under the MIT License. See `LICENSE.md` for more information.

## Contact

[**@perzanko**](mailto:perzankowski.kacper@gmail.com)

---

Project Link: [https://github.com/perzanko/blurhash-elixir](https://github.com/perzanko/blurhash-elixir)

