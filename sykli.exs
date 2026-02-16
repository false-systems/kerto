#!/usr/bin/env elixir

Mix.install([{:sykli_sdk, "~> 0.3.0"}])

Code.eval_string("""
use Sykli

pipeline do
  task "deps" do
    run "mix deps.get"
    inputs ["mix.exs", "mix.lock"]
  end

  task "compile" do
    run "mix compile --warnings-as-errors"
    after_ ["deps"]
    inputs ["**/*.ex", "mix.exs"]
  end

  task "format" do
    run "mix format --check-formatted"
    inputs ["**/*.ex", "**/*.exs"]
  end

  task "test" do
    run "mix test"
    after_ ["compile"]
    inputs ["**/*.ex", "**/*.exs"]
  end
end
""")
