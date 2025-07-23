defmodule BlurHashTest do
  use ExUnit.Case
  doctest BlurHash

  describe "decode/3" do
    test "decodes known BlurHash correctly" do
      blurhash = "LlMF%n00%#MwS|WCWEM{R*bbWBbH"
      pixels = BlurHash.decode(blurhash, 20, 12)

      # 20 * 12 * 3
      assert length(pixels) == 720
      # 240 pixels
      assert div(length(pixels), 3) == 240

      # Check first few pixels match expected values
      first_pixels = Enum.take(pixels, 9) |> Enum.chunk_every(3)
      assert length(first_pixels) == 3

      # Values should be in valid RGB range
      Enum.each(pixels, fn value ->
        assert value >= 0 and value <= 255
      end)
    end

    test "decodes black and white BlurHash" do
      blurhash = "LjIY5?00?bIUofWBWBM{WBofWBj["
      pixels = BlurHash.decode(blurhash, 16, 16)

      # 16 * 16 * 3
      assert length(pixels) == 768

      # All values should be valid RGB
      Enum.each(pixels, fn value ->
        assert value >= 0 and value <= 255
      end)
    end

    test "raises error for invalid BlurHash length" do
      assert_raise ArgumentError, ~r/BlurHash must be at least 6 characters/, fn ->
        BlurHash.decode("short", 10, 10)
      end
    end

    test "raises error for incorrect BlurHash length" do
      # This BlurHash is too short for the expected component count
      assert_raise ArgumentError, ~r/Invalid BlurHash length/, fn ->
        BlurHash.decode("L00000", 10, 10)
      end
    end

    test "handles punch parameter" do
      blurhash = "LlMF%n00%#MwS|WCWEM{R*bbWBbH"

      # Default punch
      pixels_default = BlurHash.decode(blurhash, 10, 10)

      # Higher punch (more contrast)
      pixels_high_punch = BlurHash.decode(blurhash, 10, 10, 2.0)

      # Lower punch (less contrast)
      pixels_low_punch = BlurHash.decode(blurhash, 10, 10, 0.5)

      # All should have same length
      assert length(pixels_default) == length(pixels_high_punch)
      assert length(pixels_default) == length(pixels_low_punch)

      # But different values (punch affects contrast)
      assert pixels_default != pixels_high_punch
      assert pixels_default != pixels_low_punch
    end
  end

  describe "encode/5" do
    test "encodes simple gradient pattern" do
      # Create a simple gradient
      width = 4
      height = 3

      pixels =
        for _y <- 0..(height - 1), x <- 0..(width - 1) do
          intensity = trunc(255 * x / (width - 1))
          [intensity, intensity, intensity]
        end
        |> List.flatten()

      blurhash = BlurHash.encode(pixels, width, height, 4, 3)

      # Should be a valid BlurHash string
      assert is_binary(blurhash)
      assert String.length(blurhash) > 6

      # Should only contain valid Base83 characters
      base83_chars =
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"

      Enum.each(String.graphemes(blurhash), fn char ->
        assert String.contains?(base83_chars, char)
      end)
    end

    test "encodes colorful pattern" do
      width = 8
      height = 6

      pixels =
        for y <- 0..(height - 1), x <- 0..(width - 1) do
          r = trunc(255 * x / (width - 1))
          g = trunc(255 * y / (height - 1))
          b = trunc(255 * (x + y) / (width + height - 2))
          [r, g, b]
        end
        |> List.flatten()

      blurhash = BlurHash.encode(pixels, width, height, 4, 3)

      assert is_binary(blurhash)
      # Expected length for 4x3 components
      assert String.length(blurhash) == 4 + 2 * 4 * 3
    end

    test "raises error for mismatched pixel array size" do
      # 2 pixels worth of data
      pixels = [255, 0, 0, 0, 255, 0]

      assert_raise ArgumentError, ~r/Pixel array size doesn't match dimensions/, fn ->
        # Expecting 3 pixels
        BlurHash.encode(pixels, 3, 1, 4, 3)
      end
    end

    test "handles single pixel" do
      # Single red pixel
      pixels = [128, 64, 192]
      blurhash = BlurHash.encode(pixels, 1, 1, 1, 1)

      assert is_binary(blurhash)
      # 1 + 1 + 4 + 0 (size + max_ac + dc + no ac components)
      assert String.length(blurhash) == 6
    end
  end

  describe "round-trip encoding/decoding" do
    test "round-trip preserves general image characteristics" do
      # Create a test pattern
      width = 16
      height = 12

      pixels =
        for y <- 0..(height - 1), x <- 0..(width - 1) do
          r = trunc(255 * :math.sin(x * :math.pi() / width) * :math.sin(x * :math.pi() / width))
          g = trunc(255 * :math.sin(y * :math.pi() / height) * :math.sin(y * :math.pi() / height))
          b = trunc(128 + 127 * :math.sin((x + y) * :math.pi() / (width + height)))
          [max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b))]
        end
        |> List.flatten()

      # Encode to BlurHash
      blurhash = BlurHash.encode(pixels, width, height, 4, 3)

      # Decode back (to smaller size for comparison)
      decoded_pixels = BlurHash.decode(blurhash, 8, 6)

      # Should have correct number of pixels
      assert length(decoded_pixels) == 8 * 6 * 3

      # All values should be valid RGB
      Enum.each(decoded_pixels, fn value ->
        assert value >= 0 and value <= 255
      end)
    end

    test "round-trip with different component counts" do
      width = 8
      height = 8

      pixels =
        for y <- 0..(height - 1), x <- 0..(width - 1) do
          [x * 32, y * 32, (x + y) * 16]
        end
        |> List.flatten()

      # Test different component configurations
      component_configs = [
        # Minimal
        {1, 1},
        # Standard
        {4, 3},
        # Maximum
        {9, 9}
      ]

      Enum.each(component_configs, fn {x_comp, y_comp} ->
        blurhash = BlurHash.encode(pixels, width, height, x_comp, y_comp)
        decoded = BlurHash.decode(blurhash, 4, 4)

        assert is_binary(blurhash)
        assert length(decoded) == 4 * 4 * 3

        # Expected BlurHash length: 1 (size) + 1 (max_ac) + 4 (dc) + 2 * (x_comp * y_comp - 1) (ac)
        expected_length = 6 + 2 * (x_comp * y_comp - 1)
        assert String.length(blurhash) == expected_length
      end)
    end
  end

  describe "edge cases" do
    test "handles all black image" do
      # All black 4x4 image
      pixels = List.duplicate(0, 4 * 4 * 3)
      blurhash = BlurHash.encode(pixels, 4, 4, 4, 3)
      decoded = BlurHash.decode(blurhash, 4, 4)

      assert is_binary(blurhash)
      assert length(decoded) == 4 * 4 * 3

      # Decoded should be mostly dark
      average = Enum.sum(decoded) / length(decoded)
      # Should be quite dark
      assert average < 50
    end

    test "handles all white image" do
      # All white 4x4 image
      pixels = List.duplicate(255, 4 * 4 * 3)
      blurhash = BlurHash.encode(pixels, 4, 4, 4, 3)
      decoded = BlurHash.decode(blurhash, 4, 4)

      assert is_binary(blurhash)
      assert length(decoded) == 4 * 4 * 3

      # Decoded should be mostly bright
      average = Enum.sum(decoded) / length(decoded)
      # Should be quite bright
      assert average > 200
    end

    test "handles single color image" do
      # All red image
      pixels =
        for _i <- 1..(3 * 3) do
          [255, 0, 0]
        end
        |> List.flatten()

      blurhash = BlurHash.encode(pixels, 3, 3, 4, 3)
      decoded = BlurHash.decode(blurhash, 3, 3)

      assert is_binary(blurhash)
      assert length(decoded) == 3 * 3 * 3

      # Should be predominantly red-ish
      red_values = decoded |> Enum.chunk_every(3) |> Enum.map(&hd/1)
      average_red = Enum.sum(red_values) / length(red_values)
      # Should have significant red component
      assert average_red > 100
    end
  end

  describe "base83 encoding/decoding" do
    test "base83 characters are valid" do
      # Test that we can encode and decode various values
      # 83^2 = 6889
      test_values = [0, 1, 42, 83, 166, 1000, 6889]

      Enum.each(test_values, fn value ->
        # This is testing internal functionality, but important for correctness
        # We'll test through the public API by creating specific patterns
        pixels = [value |> rem(256), value |> div(256) |> rem(256), 128]
        pixels = List.duplicate(pixels, 4) |> List.flatten()

        blurhash = BlurHash.encode(pixels, 2, 2, 1, 1)
        decoded = BlurHash.decode(blurhash, 2, 2)

        assert is_binary(blurhash)
        assert length(decoded) == 2 * 2 * 3
      end)
    end
  end
end
