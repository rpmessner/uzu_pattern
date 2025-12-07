defmodule UzuPattern.Pattern.Effects do
  @moduledoc """
  Audio effects and parameter functions for patterns.

  This module provides functions for setting audio parameters on events,
  including volume, panning, filters, and effects like reverb and delay.

  ## Functions

  - `gain/2` - Set volume/gain
  - `pan/2` - Set stereo pan position
  - `speed/2` - Set playback speed
  - `cut/2` - Set cut group (event stopping)
  - `room/2` - Set reverb amount
  - `delay/2` - Set delay amount
  - `lpf/2` - Set low-pass filter cutoff
  - `hpf/2` - Set high-pass filter cutoff

  ## Examples

      iex> import UzuPattern.Pattern.Effects
      iex> pattern = Pattern.new("bd sd") |> gain(0.8) |> lpf(2000)
  """

  alias UzuPattern.Pattern

  @doc """
  Set an arbitrary parameter for all events in the pattern.

  This is the generic version that allows setting any key/value pair.
  Specific functions like `gain/2`, `pan/2` provide convenience and validation.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Effects.set_param(:foo, 42)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:foo] == 42 end)
      true
  """
  def set_param(%Pattern{} = pattern, key, value) when is_atom(key) do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, key, value)} end)
    %{pattern | events: new_events}
  end

  @doc """
  Set the volume for all events in the pattern.

  Values typically range from 0.0 (silent) to 1.0 (full volume).
  Values above 1.0 are allowed for boosting quiet samples.

  ## Examples

      # Quiet background hi-hats
      s("hh*8") |> gain(0.3)

      # Emphasize the kick drum
      s("bd") |> gain(0.9) |> stack(s("sd hh") |> gain(0.5))

      # Fade out over pattern
      note("c4 e4 g4 c5") |> gain("1 0.8 0.6 0.4")

      iex> pattern = Pattern.new("bd sd hh") |> Pattern.Effects.gain(0.5)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:gain] == 0.5 end)
      true
  """
  def gain(%Pattern{} = pattern, value) when is_number(value) do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :gain, value)} end)
    %{pattern | events: new_events}
  end

  @doc """
  Set the stereo pan position for all events.

  - 0.0 = hard left
  - 0.5 = center (default)
  - 1.0 = hard right

  Create width and movement in your mix by spreading sounds across
  the stereo field.

  ## Examples

      # Hi-hats panned right
      s("hh*4") |> pan(0.8)

      # Alternating left-right pattern
      note("c4 e4 g4 c5") |> pan("0.2 0.8 0.2 0.8")

      # Keep bass centered, spread highs
      s("bd") |> pan(0.5) |> stack(s("hh") |> pan(0.9))

      iex> pattern = Pattern.new("bd sd") |> Pattern.Effects.pan(0.5)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:pan] == 0.5 end)
      true
  """
  def pan(%Pattern{} = pattern, value) when is_number(value) and value >= 0.0 and value <= 1.0 do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :pan, value)} end)
    %{pattern | events: new_events}
  end

  @doc """
  Set the playback speed of samples, affecting pitch.

  - 1.0 = normal speed and pitch
  - 2.0 = double speed, one octave higher
  - 0.5 = half speed, one octave lower
  - Negative values play in reverse

  For samples, speed changes both tempo and pitch. Use for pitch
  shifting, time-stretching effects, or playing samples backwards.

  ## Examples

      # Pitch up a break
      s("breaks") |> speed(1.5)

      # Play sample backwards
      s("vocal") |> speed(-1)

      # Varying speeds for texture
      s("bd") |> speed("1 0.5 1.5 0.75")

      iex> pattern = Pattern.new("bd sd") |> Pattern.Effects.speed(2.0)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:speed] == 2.0 end)
      true
  """
  def speed(%Pattern{} = pattern, value) when is_number(value) and value > 0.0 do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :speed, value)} end)
    %{pattern | events: new_events}
  end

  @doc """
  Assign events to a cut group - new events cut off previous ones in the same group.

  Essential for realistic hi-hat patterns where an open hi-hat is cut
  by a closed one, or for gating long samples.

  ## Examples

      # Closed hi-hat cuts off open hi-hat
      s("hh:1 hh:0 hh:1 hh:0") |> cut(1)

      # Long pad sample cut by retriggering
      s("pad:long") |> cut(2)

      iex> pattern = Pattern.new("bd sd") |> Pattern.Effects.cut(1)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:cut] == 1 end)
      true
  """
  def cut(%Pattern{} = pattern, group) when is_integer(group) and group >= 0 do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :cut, group)} end)
    %{pattern | events: new_events}
  end

  @doc """
  Add reverb to the pattern, placing sounds in a virtual space.

  - 0.0 = completely dry (no reverb)
  - 0.5 = balanced mix
  - 1.0 = fully wet (all reverb)

  Creates depth and atmosphere. Use sparingly on drums, more on
  melodic elements.

  ## Examples

      # Snare with room ambience
      s("~ sd ~ sd") |> room(0.3)

      # Ambient pad with lots of reverb
      note("c3 eb3 g3") |> s("sine") |> room(0.8)

      # Dry kick, wet everything else
      s("bd") |> stack(s("hh sd") |> room(0.4))

      iex> pattern = Pattern.new("bd sd") |> Pattern.Effects.room(0.5)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:room] == 0.5 end)
      true
  """
  def room(%Pattern{} = pattern, value) when is_number(value) and value >= 0.0 and value <= 1.0 do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :room, value)} end)
    %{pattern | events: new_events}
  end

  @doc """
  Add echo/delay effect to the pattern.

  - 0.0 = no delay
  - 0.5 = balanced dry/wet mix
  - 1.0 = fully delayed signal

  Creates rhythmic echoes that sync to the tempo. Great for dub
  effects, thickening sounds, or creating polyrhythmic textures.

  ## Examples

      # Dub-style delay on snare
      s("~ sd ~ ~") |> delay(0.5)

      # Subtle thickening on melody
      note("c4 e4 g4") |> s("piano") |> delay(0.2)

      # Delay on hi-hats for texture
      s("hh*4") |> delay(0.3) |> gain(0.6)

      iex> pattern = Pattern.new("bd sd") |> Pattern.Effects.delay(0.25)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:delay] == 0.25 end)
      true
  """
  def delay(%Pattern{} = pattern, value) when is_number(value) and value >= 0.0 and value <= 1.0 do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :delay, value)} end)
    %{pattern | events: new_events}
  end

  @doc """
  Apply a low-pass filter, cutting high frequencies above the cutoff.

  - Lower values = darker, more muffled sound
  - Higher values (10000+) = brighter, more open
  - 20000 = essentially no filtering

  Essential for creating movement, builds, and that classic filter sweep.

  ## Examples

      # Muffled kick drum
      s("bd*4") |> lpf(500)

      # Filter sweep on melody
      note("c4 e4 g4") |> lpf("200 500 1000 2000")

      # Acid bassline filter
      note("c2*8") |> s("sawtooth") |> lpf("100 400 800 400")

      iex> pattern = Pattern.new("bd sd") |> Pattern.Effects.lpf(1000)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:lpf] == 1000 end)
      true
  """
  def lpf(%Pattern{} = pattern, frequency) when is_number(frequency) and frequency >= 0 and frequency <= 20_000 do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :lpf, frequency)} end)
    %{pattern | events: new_events}
  end

  @doc """
  Apply a high-pass filter, cutting low frequencies below the cutoff.

  - Lower values (20-100) = subtle low-end cleanup
  - Mid values (200-500) = thinner, more focused sound
  - Higher values = telephone/radio effect

  Useful for cleaning up muddy mixes or creating contrast.

  ## Examples

      # Remove low rumble from hi-hats
      s("hh*8") |> hpf(300)

      # Radio effect on vocal
      s("vocal") |> hpf(500) |> lpf(3000)

      # Buildups - sweep the high-pass up
      s("breaks") |> hpf("100 500 1000 2000")

      iex> pattern = Pattern.new("bd sd") |> Pattern.Effects.hpf(1000)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:hpf] == 1000 end)
      true
  """
  def hpf(%Pattern{} = pattern, frequency) when is_number(frequency) and frequency >= 0 and frequency <= 20_000 do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :hpf, frequency)} end)
    %{pattern | events: new_events}
  end
end
