# Contributing to UzuPattern

Thank you for your interest in contributing to UzuPattern! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Adding New Functions](#adding-new-functions)
- [Testing](#testing)
- [Code Style](#code-style)
- [Documentation](#documentation)
- [Submitting Changes](#submitting-changes)

## Code of Conduct

Be respectful, inclusive, and constructive in all interactions. We're all here to make great music software!

## Getting Started

### Prerequisites

- Elixir 1.14 or later
- Erlang/OTP 25 or later
- Git

### Setup

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/uzu_pattern.git
   cd uzu_pattern
   ```

3. Add the upstream remote:
   ```bash
   git remote add upstream https://github.com/rpmessner/uzu_pattern.git
   ```

4. Install dependencies:
   ```bash
   mix deps.get
   ```

5. Run tests to verify everything works:
   ```bash
   mix test
   ```

## Development Workflow

### Keeping Your Fork Updated

```bash
git fetch upstream
git checkout main
git merge upstream/main
```

### Creating a Feature Branch

```bash
git checkout -b feature/your-feature-name
```

Use descriptive branch names:
- `feature/add-euclid-function` for new features
- `fix/iter-wrapping-bug` for bug fixes
- `docs/improve-readme` for documentation

## Adding New Functions

When implementing a new pattern transformation function, follow this workflow:

### 1. Check the Roadmap

Review [ROADMAP.md](ROADMAP.md) to see if your function is planned. If not, open an issue to discuss it first.

### 2. Understand Strudel.js Behavior

- Check the [Strudel.js documentation](https://strudel.cc/learn/)
- Test the function in the Strudel REPL to understand exact behavior
- Note any edge cases or special behaviors

### 3. Implement the Function

Add your function to `lib/uzu_pattern/pattern.ex`:

```elixir
@doc """
Brief description of what the function does.

Longer explanation with details about behavior and use cases.

## Examples

    iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.your_function(args)
    iex> events = Pattern.events(pattern)
    iex> # Expected result
"""
def your_function(%__MODULE__{} = pattern, arg) when guard do
  # Implementation
end
```

**Function Placement:**
- **Immediate transforms** (modify events directly): Add after other time modifiers
- **Deferred transforms** (cycle-aware): Add after conditional modifiers section
- Add transform types to `@type transform` if needed

### 4. Write Tests

Add comprehensive tests to `test/uzu_pattern_test.exs`:

```elixir
describe "your_function/2" do
  test "basic behavior" do
    pattern = Pattern.new("bd sd") |> Pattern.your_function(arg)
    events = Pattern.events(pattern)

    # Assertions
  end

  test "maintains event properties" do
    # Test that sound, sample, params are preserved
  end

  test "edge cases" do
    # Test empty patterns, boundary conditions, etc.
  end
end
```

### 5. Update Documentation

When you add a new function:

1. **Add to ROADMAP.md**: Move from planned phase to "Implemented"
2. **Add to README.md**: Include in appropriate feature section with example
3. **Add docstring**: Use `@doc` with examples (shown above)
4. **Update CHANGELOG.md**: Add to "Unreleased" section

## Testing

### Running Tests

```bash
# Run all tests
mix test

# Run tests with coverage
mix test --cover

# Run tests in watch mode (requires mix test.watch)
mix test.watch

# Run a specific test file
mix test test/uzu_pattern_test.exs

# Run a specific test
mix test test/uzu_pattern_test.exs:123
```

### Test Requirements

- All new functions must have tests
- Tests should cover:
  - Basic functionality
  - Edge cases (empty patterns, boundary conditions)
  - Event property preservation
  - Cycle-aware behavior (if applicable)
- Aim for meaningful test names that describe what's being tested

### Test Structure

```elixir
describe "function_name/arity" do
  test "describes what it tests" do
    # Arrange
    pattern = Pattern.new("bd sd")

    # Act
    result = Pattern.function_name(pattern, args)

    # Assert
    assert expected == result
  end
end
```

## Code Style

### Formatting

We use `mix format`. Before committing:

```bash
mix format
```

CI will fail if code is not properly formatted.

### Credo

Run Credo for style suggestions:

```bash
mix credo --strict
```

Fix any issues before submitting a PR.

### Dialyzer

Run Dialyzer for type checking:

```bash
mix dialyzer
```

### Code Quality Checklist

- [ ] Code is formatted (`mix format`)
- [ ] No Credo warnings (`mix credo --strict`)
- [ ] No Dialyzer warnings (`mix dialyzer`)
- [ ] All tests pass (`mix test`)
- [ ] Test coverage is maintained or improved
- [ ] Documentation is complete and accurate

## Documentation

### Docstrings

Every public function must have a `@doc` string with:

1. **Brief description** (one line)
2. **Detailed explanation** (optional, for complex functions)
3. **Examples** using doctests
4. **Return value** description (if not obvious)

Example:

```elixir
@doc """
Speed up a pattern by a factor.

Compresses all event times and durations by dividing by the factor.
Events that would occur after cycle boundary (time >= 1.0) are filtered out.

## Examples

    iex> pattern = Pattern.new("bd sd") |> Pattern.fast(2)
    iex> events = Pattern.events(pattern)
    iex> Enum.at(events, 1).time
    0.25

## See also
- `slow/2` - The inverse operation
"""
```

### Module Documentation

Update `UzuPattern.Pattern` moduledoc if adding new categories of functions.

## Submitting Changes

### Commit Messages

Write clear, descriptive commit messages:

```
Brief summary (50 chars or less)

More detailed explanation if needed. Wrap at 72 characters.
Explain what changed and why, not how (code shows how).

- Bullet points are okay
- Use present tense: "Add feature" not "Added feature"
- Reference issues: "Fixes #123"
```

**For new functions:**

```
Add iter/2 function for rotating patterns

Implements cycle-aware pattern rotation that shifts the start position
by one subdivision each cycle. Based on Strudel.js iter function.

- Added iter/2 to Pattern module
- Added comprehensive tests
- Updated ROADMAP.md and README.md
- Resolves #42
```

### Pull Request Process

1. **Update documentation**
   - CHANGELOG.md (add to "Unreleased" section)
   - README.md (if adding features)
   - ROADMAP.md (if implementing planned features)

2. **Ensure CI passes**
   - All tests pass
   - Code is formatted
   - No Credo warnings
   - No Dialyzer errors

3. **Create the PR**
   - Use a descriptive title
   - Reference any related issues
   - Describe what changed and why
   - Include examples if adding features

4. **PR Template**
   ```markdown
   ## Description
   Brief description of changes

   ## Type of Change
   - [ ] Bug fix
   - [ ] New feature
   - [ ] Documentation update
   - [ ] Performance improvement

   ## Checklist
   - [ ] Tests added/updated
   - [ ] Documentation updated
   - [ ] CHANGELOG.md updated
   - [ ] All CI checks pass

   ## Related Issues
   Fixes #123
   ```

5. **Review Process**
   - Be responsive to feedback
   - Make requested changes in new commits
   - Once approved, maintainers will merge

### Merge Requirements

- At least one approving review
- All CI checks passing
- No merge conflicts
- Up to date with main branch

## Questions?

- Open an issue for bugs or feature requests
- Start a discussion for questions about architecture or design
- Check existing issues and PRs first

## Recognition

Contributors will be acknowledged in:
- CHANGELOG.md (for significant contributions)
- Git history (all commits)
- Release notes

Thank you for contributing to UzuPattern! 🎵
