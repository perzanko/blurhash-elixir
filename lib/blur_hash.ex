defmodule BlurHash do
  @moduledoc """
  Pure Elixir implementation of Blurhash algorithm with no additional dependencies.

  Blurhash is an algorithm by Dag Ågren of Wolt that decodes an image to a very compact (~ 20-30 bytes) ASCII string representation, which can be then decoded into a blurred placeholder image. See the main repo (https://github.com/woltapp/blurhash) for the rationale and details.

  This library supports only encoding.

  More details on https://blurha.sh/
  """
  @moduledoc since: "1.0.0"

  @digit_characters "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"

  @doc """
  Calculates the blur hash from the given pixels

  Returns Blurhash string

  ## Examples

      iex> BlurHash.encode(pixels, 30, 30, 4, 3)
      "LEHV6nWB2yk8pyo0adR*.7kCMdnj"

  """
  @doc since: "1.0.0"

  @type pixels :: [integer()]
  @type width :: integer()
  @type height :: integer()
  @type components_y :: integer()
  @type components_x :: integer()
  @type hash :: String.t()

  @spec encode(pixels, width, height, components_y, components_x) :: hash
  def encode(pixels, width, height, components_y, components_x) do
    size_flag = components_x - 1 + (components_y - 1) * 9
    [dc | ac] = get_factors(pixels, width, height, components_y, components_x)

    hash = encode_83(size_flag, 1)

    cond do
      length(ac) > 0 ->
        actual_maximum_value =
          ac
          |> Enum.map(&Enum.max/1)
          |> Enum.max()

        quantised_maximum_value =
          floor(Enum.max([0.0, Enum.min([82.0, floor(actual_maximum_value * 166 - 0.5)])]) / 1)

        maximum_value = (quantised_maximum_value + 1) / 166
        hash = hash <> encode_83(quantised_maximum_value, 1) <> encode_83(encode_dc(dc), 4)

        Enum.reduce(
          ac,
          hash,
          fn factor, acc ->
            acc <>
              (factor
               |> encode_ac(maximum_value)
               |> encode_83(2))
          end
        )

      true ->
        maximum_value = 1

        hash <>
          encode_83(0, 1) <>
          (encode_dc(dc)
           |> encode_83(4))
    end
  end

  defp get_factors(pixels, width, height, components_y, components_x) do
    bytes_per_pixel = 4
    bytes_per_row = width * bytes_per_pixel
    scale = 1 / (width * height)

    tasks =
      for y <- 0..(components_y - 1),
          x <- 0..(components_x - 1),
          reduce: [] do
        acc ->
          normalisation = if x === 0 && y === 0, do: 1, else: 2

          acc ++
            [
              Task.async(fn ->
                [total_r, total_g, total_b] =
                  for x1 <- 0..(width - 1),
                      y1 <- 0..(height - 1),
                      reduce: [0, 0, 0] do
                    rgb ->
                      basis =
                        normalisation *
                          :math.cos(:math.pi() * x * x1 / width) *
                          :math.cos(:math.pi() * y * y1 / height)

                      [r, g, b] = rgb

                      [
                        r +
                          basis *
                            s_rgb_to_linear(
                              Enum.fetch!(pixels, bytes_per_pixel * x1 + 0 + bytes_per_row * y1)
                            ),
                        g +
                          basis *
                            s_rgb_to_linear(
                              Enum.fetch!(pixels, bytes_per_pixel * x1 + 1 + bytes_per_row * y1)
                            ),
                        b +
                          basis *
                            s_rgb_to_linear(
                              Enum.fetch!(pixels, bytes_per_pixel * x1 + 2 + bytes_per_row * y1)
                            )
                      ]
                  end

                [total_r * scale, total_g * scale, total_b * scale]
              end)
            ]
      end

    tasks
    |> Task.yield_many(60_000)
    |> Enum.map(fn {_, {:ok, result}} -> result end)
  end

  defp encode_83(_, 0), do: ""

  defp encode_83(value, length) do
    for i <- 1..length,
        reduce: "" do
      hash ->
        digit =
          floor(
            rem(
              floor(floor(value / 1) / :math.pow(83, length - i)),
              83
            ) / 1
          )

        hash = hash <> String.at(@digit_characters, digit)
    end
  end

  defp encode_dc([r, g, b]) do
    r = linear_to_s_rgb(r)
    g = linear_to_s_rgb(g)
    b = linear_to_s_rgb(b)
    r * 0x10000 + g * 0x100 + b
  end

  defp encode_ac([r, g, b], maximum_value) do
    quant = fn value ->
      sign = if value / maximum_value < 0, do: -1, else: 1

      floor(
        Enum.max([
          0.0,
          Enum.min([
            18.0,
            floor(sign * :math.pow(abs(value / maximum_value), 0.5) * 9 + 9.5)
          ])
        ]) / 1
      )
    end

    quant.(r) * 19 * 19 + quant.(g) * 19 + quant.(b)
  end

  defp s_rgb_to_linear(value) do
    v = value / 255.0

    if v <= 0.04045 do
      v / 12.92
    else
      :math.pow((v + 0.055) / 1.055, 2.4)
    end
  end

  defp linear_to_s_rgb(value) do
    v = max(0, min(1, value))

    if v <= 0.0031308 do
      round(v * 12.92 * 255 + 0.5)
    else
      round((1.055 * :math.pow(v, 1 / 2.4) - 0.055) * 255 + 0.5)
    end
  end
end
