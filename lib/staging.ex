# Usage: mix run examples/rate_limiter.exs
#
# Hit Ctrl+C twice to stop it.
#
# This is an example of using manual demand for
# doing rate limiting work on a consumer.
alias Experimental.{GenStage}

defmodule CodeNode do
  use GenStage

  def init({name, counter}) do
    send(self(), :inc)
    {:producer, {name, counter, nil}}
  end

  def handle_demand(demand, {name, counter, value}) when demand > 0 do
    # If the counter is 3 and we ask for 2 items, we will
    # emit the items 3 and 4, and set the state to 5.
    events = Enum.to_list(counter..counter+demand-1)
    {:noreply, events, {name, counter + demand, value}}
  end

  def handle_info(:inc, {name = "A", counter, value}) do
    # This callback is invoked by the Process.send_after/3 message below.

    Process.send_after(self(), :inc, Enum.random(1..5))
    IO.puts "#{name} is now #{counter + 1}"
    {:noreply, [], {name, counter + 1, value}}
  end
  def handle_info(:inc, {name, counter, value}) do
    # This callback is invoked by the Process.send_after/3 message below.

    Process.send_after(self(), :inc, Enum.random(1..5))
    IO.puts "#{name} is now #{counter + 1}"
    {:noreply, [], {name, counter + 1, value}}
  end


  def handle_info({:result, new_result}, {name, counter, _}) do
    # This callback is invoked by the Process.send_after/3 message below.
    IO.puts "result for #{name}: #{new_result} #{inspect self()}"
    {:noreply, [], {name, counter, new_result}}
  end
end

defmodule CodeRunner do
  use GenStage

  def init(_) do
    {:consumer, %{}}
  end

  def handle_subscribe(:producer, opts, from, producers) do
    # We will only allow max_demand events every 5000 miliseconds
    pending = opts[:max_demand] || 1

    # Register the producer in the state
    producers = Map.put(producers, from, {pending})
    # Ask for the pending events and schedule the next time around
    producers = ask_and_schedule(producers, from)

    # Returns manual as we want control over the demand
    {:manual, producers}
  end

  def handle_cancel(_, from, producers) do
    # Remove the producers from the map on unsubscribe
    {:noreply, [], Map.delete(producers, from)}
  end

  def handle_events([event], from, producers) do
    # Bump the amount of pending events for the given producer
    producers = Map.update!(producers, from, fn {pending} ->
      {pending + 1}
    end)


    {pid, ref} = from

    # Consume the events by printing them.
    IO.puts("handle event #{event} for #{inspect pid}")
    result = 2 * event
    Process.send_after(self(), {:process_result, pid, result, from}, Enum.random(1..500))

    # A producer_consumer would return the processed events here.
    {:noreply, [], producers}
  end

  def handle_info({:process_result, pid, result, from}, producers) do
    # This callback is invoked by the Process.send_after/3 message below.
    send(pid, {:result, result})
    {:noreply, [], ask_and_schedule(producers, from)}
  end

  defp ask_and_schedule(producers, from) do
    case producers do
      %{^from => {pending}} ->
        GenStage.ask(from, pending)
        Map.put(producers, from, {0})
      %{} ->
        producers
    end
  end
end

{:ok, codeA} = GenStage.start_link(CodeNode, {"A", 0})      # starting from zero
{:ok, codeB} = GenStage.start_link(CodeNode, {"B", 0})      # starting from zero
{:ok, runner} = GenStage.start_link(CodeRunner, :ok) # expand by 2

# # Ask for 10 items every 2 seconds.
GenStage.sync_subscribe(runner, to: codeA, max_demand: 1, interval: 2000)
GenStage.sync_subscribe(runner, to: codeB, max_demand: 1, interval: 2000)
Process.sleep(:infinity)