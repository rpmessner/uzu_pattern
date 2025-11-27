# UzuPattern Feature Roadmap

Pattern orchestration library for Strudel.js-style transformations. This roadmap tracks feature parity with [Strudel.js](https://strudel.cc/).

## ✅ Implemented (v0.6.0)

### Core Infrastructure
- [x] `Pattern` struct with events and transforms
- [x] `new/1` - Create from mini-notation string
- [x] `from_events/1` - Create from event list
- [x] `query/2` - Get events for a specific cycle
- [x] `events/1` - Extract raw events

### Time Modifiers
- [x] `fast/2` - Speed up pattern by factor
- [x] `slow/2` - Slow down pattern by factor
- [x] `rev/1` - Reverse pattern
- [x] `early/2` - Shift pattern earlier (wraps)
- [x] `late/2` - Shift pattern later (wraps)
- [x] `ply/2` - Repeat each event N times (v0.2.0)
- [x] `compress/3` - Fit pattern into time segment (v0.2.0)
- [x] `zoom/3` - Extract and expand time segment (v0.2.0)
- [x] `linger/2` - Repeat fraction of pattern (v0.2.0)

### Combinators
- [x] `stack/1` - Play patterns simultaneously
- [x] `cat/1` - Play patterns sequentially
- [x] `palindrome/1` - Forward then backward

### Conditional Modifiers (Cycle-Aware)
- [x] `every/3` - Apply function every N cycles
- [x] `sometimes_by/3` - Apply with probability
- [x] `sometimes/2` - 50% probability
- [x] `often/2` - 75% probability
- [x] `rarely/2` - 25% probability
- [x] `iter/2` - Rotate pattern start each cycle (v0.2.0)
- [x] `iter_back/2` - Rotate in reverse (v0.2.0)
- [x] `first_of/3` - Apply on first of N cycles (v0.3.0)
- [x] `last_of/3` - Apply on last of N cycles (v0.3.0)
- [x] `when_fn/3` - Apply when condition is true (v0.3.0)
- [x] `chunk/3` - Apply to rotating chunks (v0.3.0)
- [x] `chunk_back/3` - Chunk in reverse (v0.3.0)

### Structural Filtering
- [x] `struct_fn/2` - Apply rhythmic structure (v0.3.0)
- [x] `mask/2` - Silence based on pattern (v0.3.0)

### Degradation
- [x] `degrade/1` - Remove ~50% of events randomly
- [x] `degrade_by/2` - Remove with custom probability

### Stereo
- [x] `jux/2` - Apply function to right channel

### Effects & Parameters
- [x] `gain/2` - Set volume (v0.4.0)
- [x] `pan/2` - Set stereo position (v0.4.0)
- [x] `speed/2` - Set playback speed (v0.4.0)
- [x] `cut/2` - Cut group assignment (v0.4.0)
- [x] `room/2` - Reverb amount (v0.4.0)
- [x] `delay/2` - Delay amount (v0.4.0)
- [x] `lpf/2` - Low-pass filter cutoff (v0.4.0)
- [x] `hpf/2` - High-pass filter cutoff (v0.4.0)

### Advanced Combinators
- [x] `jux_by/3` - Partial jux effect (v0.5.0)
- [x] `append/2` - Append pattern (v0.5.0)
- [x] `superimpose/2` - Stack with transformation (v0.5.0)
- [x] `off/3` - Delayed copy with transform (v0.5.0)
- [x] `echo/3` - Multiple delayed copies (v0.5.0)
- [x] `striate/2` - Interleave slices (v0.5.0)
- [x] `chop/2` - Slice into pieces (v0.5.0)

### Advanced Rhythm
- [x] `euclid/3` - Euclidean rhythm (v0.6.0)
- [x] `euclid_rot/4` - Euclidean with rotation (v0.6.0)
- [x] `swing/2` - Swing timing (v0.6.0)
- [x] `swing_by/3` - Parameterized swing (v0.6.0)

---

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   UzuParser     │────▶│   UzuPattern    │────▶│    Waveform     │
│   (parsing)     │     │  (transforms)   │     │    (audio)      │
│                 │     │                 │     │                 │
│ • parse/1       │     │ • Pattern struct│     │ • OSC           │
│ • mini-notation │     │ • fast/slow/rev │     │ • SuperDirt     │
│ • [%Event{}]    │     │ • stack/cat     │     │ • MIDI          │
│                 │     │ • every/when    │     │ • scheduling    │
│                 │     │ • query/2       │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Integration with Waveform

UzuPattern provides a `query/2` function that Waveform can use for cycle-aware scheduling:

```elixir
# In kino_harmony or harmony_server:
pattern =
  "bd sd hh cp"
  |> UzuPattern.new()
  |> UzuPattern.Pattern.fast(2)
  |> UzuPattern.Pattern.every(4, &UzuPattern.Pattern.rev/1)

# Create query function for Waveform
query_fn = fn cycle -> UzuPattern.query(pattern, cycle) end

# Pass to Waveform's PatternScheduler
Waveform.PatternScheduler.schedule_pattern(:drums, query_fn)
```

See `HANDOFF.md` for detailed integration documentation.

## Contributing

When implementing a new function:

1. Add to `lib/uzu_pattern/pattern.ex`
2. Add tests to `test/uzu_pattern_test.exs`
3. Update this roadmap (move to Implemented)
4. Update `CHANGELOG.md`

## References

- [Strudel.js Documentation](https://strudel.cc/learn/)
- [TidalCycles Documentation](https://tidalcycles.org/docs/)
- [UzuParser](https://github.com/rpmessner/uzu_parser)
- [Waveform](https://github.com/rpmessner/waveform)
