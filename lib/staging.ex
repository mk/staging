# Usage: mix run examples/rate_limiter.exs
#
# Hit Ctrl+C twice to stop it.
#
# This is an example of using manual demand for
# doing rate limiting work on a consumer.
alias Experimental.{GenStage}

defmodule CodeNode do
  use GenStage

  def init(counter) do
    send(self(), :inc)
    {:producer, counter}
  end

  def handle_demand(demand, counter) when demand > 0 do
    # If the counter is 3 and we ask for 2 items, we will
    # emit the items 3 and 4, and set the state to 5.
    events = Enum.to_list(counter..counter+demand-1)
    {:noreply, events, counter + demand}
  end

  def handle_info(:inc, counter) do
    # This callback is invoked by the Process.send_after/3 message below.

    Process.send_after(self(), :inc, 500)
    {:noreply, [], counter + 1}
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

    # Consume the events by printing them.
    IO.puts(event)
    Process.sleep 3000

    # A producer_consumer would return the processed events here.
    {:noreply, [], producers}
  end

  def handle_info({:ask, from}, producers) do
    # This callback is invoked by the Process.send_after/3 message below.
    {:noreply, [], ask_and_schedule(producers, from)}
  end

  defp ask_and_schedule(producers, from) do
    case producers do
      %{^from => {pending}} ->
        GenStage.ask(from, pending)
        Process.send_after(self(), {:ask, from}, 1000)
        Map.put(producers, from, {0})
      %{} ->
        producers
    end
  end
end

{:ok, a} = GenStage.start_link(CodeNode, 0)      # starting from zero
{:ok, b} = GenStage.start_link(CodeRunner, :ok) # expand by 2

# # Ask for 10 items every 2 seconds.
GenStage.sync_subscribe(b, to: a, max_demand: 1, interval: 2000)
Process.sleep(:infinity)