# Usage: mix run examples/rate_limiter.exs
#
# Hit Ctrl+C twice to stop it.
#
# This is an example of using manual demand for
# doing rate limiting work on a consumer.
alias Experimental.{GenStage}

defmodule CodeNode do
  use GenStage

  defstruct name: nil, code: nil, result: nil, has_demand: false

  def init({name, counter}) do
    send(self(), :update_code)
    {:producer, %CodeNode{name: name, code: counter}}
  end

  def handle_demand(1 = demand, %CodeNode{name: name, has_demand: false} = node) do
    IO.puts "#{name} has no evaluation demand"
    {:noreply, [], node} # return no event unless we're waiting for execution
  end
  def handle_demand(1 = demand, %CodeNode{name: name, code: code, has_demand: true} = node) when demand > 0 do
    IO.puts "#{name} has demand to evaulate `#{code}`"
    events = [node] # this will always emit just one event with the current code
    {:noreply, events, node}
  end

  def handle_info(:update_code, %CodeNode{name: name, code: code} = node) do
    # This callback is invoked by the Process.send_after/3 message below.
    Process.send_after(self(), :update_code, Enum.random(2..200))
    IO.puts "#{name} changed to `#{code + 1}`"
    {:noreply, [], %{node | code: code + 1, has_demand: true}}
  end


  def handle_info({:result, new_result, code_for_result}, %CodeNode{name: name, code: code} = node) do
    # This callback is invoked by the Process.send_after/3 message below.
    if code_for_result == code do
      IO.puts "#{name} got result #{new_result} evaluating `#{code_for_result}`"
      {:noreply, [], %{node | result: new_result, has_demand: false}}
    else
      IO.puts "#{name} got stale result #{new_result} evaluating `#{code_for_result}` while interested in result for `#{code}`"
      {:noreply, [], node}
    end
  end
end

defmodule CodeRunner do
  use GenStage

  defstruct producers: [], is_executing: false

  def init(_) do
    {:consumer, %CodeRunner{}}
  end

  def handle_subscribe(:producer, opts, from, state = %CodeRunner{ producers: producers }) do
    # We will only allow max_demand events every 5000 miliseconds
    pending = 1

    # Register the producer in the state
    state = Map.put(state, :producers, [from | producers])
    GenStage.ask(from, 1)

    # Returns manual as we want control over the demand
    {:manual, state}
  end

  def handle_cancel(_, from, state) do
    # Remove the state from the map on unsubscribe
    {:noreply, [], Map.delete(state, from)}
  end

  def handle_events([%CodeNode{name: name, code: code}], from, state = %{is_executing: false}) do
    {pid, ref} = from

    # Consume the events by printing them.
    IO.puts("#{name} starting evaluation for `#{code}`")
    result = 2 * code
    Process.send_after(self(), {:process_result, pid, result, from, code}, Enum.random(1..500))

    # A producer_consumer would return the processed events here.
    {:noreply, [], %{state| is_executing: true}}
  end
  def handle_events([%CodeNode{name: name, code: code}], from, state) do
    IO.puts("busy in handle_events for #{name} (`#{code}`).")
    {:noreply, [], %{state| is_executing: true}}
  end

  def handle_info({:process_result, pid, result, from, code}, state) do
    # This callback is invoked by the Process.send_after/3 message below.
    send(pid, {:result, result, code})
    {:noreply, [], ask_and_schedule(%{state| is_executing: false})}
  end
  def handle_info(:ask_if_idle, state = %{is_executing: false}) do
    {:noreply, [], ask_and_schedule(state)}
  end
  def handle_info(_, state) do
    {:noreply, [], state}
  end

  defp ask_and_schedule(state = %CodeRunner{ producers: producers, is_executing: false}) do
    for producer <- producers, do: GenStage.ask(producer, 1)
    Process.send_after(self(), :ask_if_idle, 100)
    state
  end
  defp ask_and_schedule(state) do
    state
  end
end

{:ok, codeA} = GenStage.start_link(CodeNode, {"A", 0})      # starting from zero
{:ok, codeB} = GenStage.start_link(CodeNode, {"B", 0})      # starting from zero
{:ok, runner} = GenStage.start_link(CodeRunner, :ok) # expand by 2

# # Ask for 10 items every 2 seconds.
GenStage.sync_subscribe(runner, to: codeA, max_demand: 1, interval: 2000)
GenStage.sync_subscribe(runner, to: codeB, max_demand: 1, interval: 2000)
Process.sleep(:infinity)