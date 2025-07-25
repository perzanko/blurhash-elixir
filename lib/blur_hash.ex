defmodule BlurHash do
  @moduledoc """
  BlurHash implementation in Elixir.

  BlurHash is a compact representation of a placeholder for an image.
  It applies a DCT transform to the image data and encodes the components
  using a base 83 encoding.

  ## Examples

      iex> pixels = BlurHash.decode("LlMF%n00%#MwS|WCWEM{R*bbWBbH", 4, 3)
      iex> length(pixels)
      36
      iex> Enum.all?(pixels, fn x -> x >= 0 and x <= 255 end)
      true

  """

  # Base83 character set for encoding
  @base83_chars "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"
  @base83_chars_list String.graphemes(@base83_chars)
  @base83_chars_map @base83_chars_list
                    |> Enum.with_index()
                    |> Enum.into(%{})

  @doc """
  Encode an image to a BlurHash string.

  ## Parameters
  - `pixels`: List of RGB pixel values [r, g, b, r, g, b, ...]
  - `width`: Image width
  - `height`: Image height
  - `x_components`: Number of components along X axis (1-9)
  - `y_components`: Number of components along Y axis (1-9)

  ## Returns
  BlurHash string

  ## Examples

      iex> pixels = [255, 0, 0, 0, 255, 0, 0, 0, 255]
      iex> blurhash = BlurHash.encode(pixels, 3, 1, 4, 3)
      iex> is_binary(blurhash)
      true
      iex> String.length(blurhash) > 6
      true

  """
  def encode(pixels, width, height, x_components, y_components) do
    if length(pixels) != width * height * 3 do
      raise ArgumentError, "Pixel array size doesn't match dimensions"
    end

    ac_count = x_components * y_components - 1

    # Calculate DCT factors
    factors = calculate_factors(pixels, width, height, x_components, y_components)

    # Extract DC and AC components
    dc = hd(factors)
    ac = tl(factors)

    # Encode size flag
    size_flag = x_components - 1 + (y_components - 1) * 9
    hash = encode_base83(size_flag, 1)

    # Calculate and encode maximum AC value
    {max_ac_encoded, max_ac_value} =
      if ac_count > 0 do
        actual_max = ac |> Enum.flat_map(&Tuple.to_list/1) |> Enum.map(&abs/1) |> Enum.max()
        quantised_max_ac = max(0, min(82, floor(actual_max * 166 - 0.5)))
        {quantised_max_ac, (quantised_max_ac + 1) / 166}
      else
        {0, 1.0}
      end

    hash = hash <> encode_base83(max_ac_encoded, 1)

    # Encode DC component
    dc_encoded = encode_dc(dc)
    hash = hash <> encode_base83(dc_encoded, 4)

    # Encode AC components
    ac_encoded = Enum.map(ac, fn component -> encode_ac(component, max_ac_value) end)
    ac_hash = Enum.map(ac_encoded, fn value -> encode_base83(value, 2) end) |> Enum.join()

    hash <> ac_hash
  end

  @doc """
  Decode a BlurHash string to RGB pixel data.

  ## Parameters
  - `blurhash`: BlurHash string
  - `width`: Desired output width
  - `height`: Desired output height
  - `punch`: Contrast adjustment (default: 1.0)

  ## Returns
  List of RGB pixel values [r, g, b, r, g, b, ...]

  ## Examples

      iex> pixels = BlurHash.decode("LlMF%n00%#MwS|WCWEM{R*bbWBbH", 4, 3)
      iex> length(pixels)
      36
      iex> Enum.all?(pixels, fn x -> x >= 0 and x <= 255 end)
      true

  """
  def decode(blurhash, width, height, punch \\ 1.0) do
    if String.length(blurhash) < 6 do
      raise ArgumentError, "BlurHash must be at least 6 characters"
    end

    # Parse size flag
    size_flag = decode_base83(String.slice(blurhash, 0, 1))
    num_y = div(size_flag, 9) + 1
    num_x = rem(size_flag, 9) + 1

    expected_length = 4 + 2 * num_x * num_y

    if String.length(blurhash) != expected_length do
      raise ArgumentError,
            "Invalid BlurHash length: expected #{expected_length}, got #{String.length(blurhash)}"
    end

    # Parse maximum AC value
    max_ac_encoded = decode_base83(String.slice(blurhash, 1, 1))
    max_ac = (max_ac_encoded + 1) / 166 * punch

    # Parse DC component
    dc_encoded = decode_base83(String.slice(blurhash, 2, 4))
    dc = decode_dc(dc_encoded)

    # Parse AC components
    ac_components =
      for i <- 1..(num_x * num_y - 1) do
        start_pos = 4 + i * 2
        ac_encoded = decode_base83(String.slice(blurhash, start_pos, 2))
        decode_ac(ac_encoded, max_ac)
      end

    colors = [dc | ac_components]

    # Generate pixel data
    for y <- 0..(height - 1), x <- 0..(width - 1) do
      {r, g, b} =
        colors
        |> Enum.with_index()
        |> Enum.reduce({0.0, 0.0, 0.0}, fn {{color_r, color_g, color_b}, index},
                                           {acc_r, acc_g, acc_b} ->
          j = div(index, num_x)
          i = rem(index, num_x)
          basis = :math.cos(:math.pi() * x * i / width) * :math.cos(:math.pi() * y * j / height)
          {acc_r + color_r * basis, acc_g + color_g * basis, acc_b + color_b * basis}
        end)

      [linear_to_srgb(r), linear_to_srgb(g), linear_to_srgb(b)]
    end
    |> List.flatten()
  end

  # Private helper functions

  defp calculate_factors(pixels, width, height, x_components, y_components) do
    for y <- 0..(y_components - 1), x <- 0..(x_components - 1) do
      normalisation = if x == 0 and y == 0, do: 1.0, else: 2.0

      {r, g, b} = multiply_basis_function(pixels, width, height, x, y)
      scale = normalisation / (width * height)
      {r * scale, g * scale, b * scale}
    end
  end

  defp multiply_basis_function(pixels, width, height, x_component, y_component) do
    pixels
    |> Enum.chunk_every(3)
    |> Enum.with_index()
    |> Enum.reduce({0.0, 0.0, 0.0}, fn {[r, g, b], pixel_index}, {acc_r, acc_g, acc_b} ->
      x = rem(pixel_index, width)
      y = div(pixel_index, width)

      basis =
        :math.cos(:math.pi() * x_component * x / width) *
          :math.cos(:math.pi() * y_component * y / height)

      linear_r = srgb_to_linear(r)
      linear_g = srgb_to_linear(g)
      linear_b = srgb_to_linear(b)

      {acc_r + basis * linear_r, acc_g + basis * linear_g, acc_b + basis * linear_b}
    end)
  end

  defp encode_dc({r, g, b}) do
    rounded_r = linear_to_srgb(r)
    rounded_g = linear_to_srgb(g)
    rounded_b = linear_to_srgb(b)

    Bitwise.bsl(rounded_r, 16) + Bitwise.bsl(rounded_g, 8) + rounded_b
  end

  defp encode_ac({r, g, b}, max_value) do
    quant_r = max(0, min(18, floor(sign_pow(r / max_value, 0.5) * 9 + 9.5)))
    quant_g = max(0, min(18, floor(sign_pow(g / max_value, 0.5) * 9 + 9.5)))
    quant_b = max(0, min(18, floor(sign_pow(b / max_value, 0.5) * 9 + 9.5)))

    trunc(quant_r * 19 * 19 + quant_g * 19 + quant_b)
  end

  defp decode_dc(value) do
    r = Bitwise.bsr(value, 16)
    g = Bitwise.band(Bitwise.bsr(value, 8), 255)
    b = Bitwise.band(value, 255)

    {srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b)}
  end

  defp decode_ac(value, max_value) do
    quant_r = div(value, 19 * 19)
    quant_g = rem(div(value, 19), 19)
    quant_b = rem(value, 19)

    r = sign_pow((quant_r - 9) / 9, 2.0) * max_value
    g = sign_pow((quant_g - 9) / 9, 2.0) * max_value
    b = sign_pow((quant_b - 9) / 9, 2.0) * max_value

    {r, g, b}
  end

  defp srgb_to_linear(value) do
    v = value / 255.0

    if v <= 0.04045 do
      v / 12.92
    else
      :math.pow((v + 0.055) / 1.055, 2.4)
    end
  end

  defp linear_to_srgb(value) do
    v = max(0, min(1, value))

    result =
      if v <= 0.0031308 do
        v * 12.92 * 255
      else
        (1.055 * :math.pow(v, 1 / 2.4) - 0.055) * 255
      end

    trunc(result)
  end

  defp sign_pow(value, exp) do
    sign = if value < 0, do: -1, else: 1
    sign * :math.pow(abs(value), exp)
  end

  defp encode_base83(value, length) do
    {result, _} =
      Enum.reduce((length - 1)..0, {[], value}, fn i, {acc, val} ->
        power = trunc(:math.pow(83, i))
        digit = div(val, power)
        new_val = rem(val, power)
        {[Enum.at(@base83_chars_list, digit) | acc], new_val}
      end)

    result |> Enum.reverse() |> Enum.join()
  end

  defp decode_base83(string) do
    string
    |> String.graphemes()
    |> Enum.reduce(0, fn char, acc ->
      acc * 83 + Map.get(@base83_chars_map, char, 0)
    end)
  end
end
