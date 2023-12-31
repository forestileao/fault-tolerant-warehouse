defmodule Warehouse.Deliverator do
  alias Warehouse.Receiver
  use GenServer

  def start do
    GenServer.start(__MODULE__, [])
  end

  def init(init_arg) do
    {:ok, init_arg}
  end

  def deliver_packages(pid, packages) do
    GenServer.cast(pid, {:deliver_packages, packages})
  end

  def handle_cast({:deliver_packages, packages}, state) do
    deliver(packages)
    {:noreply, state}
  end

  defp deliver([]), do: send(Receiver, {:deliverator_idle, self()})

  defp deliver([package | remaining_packages]) do
    IO.puts("Deliverator #{inspect(self())} delivering #{inspect(package)}")
    make_delivery()
    send(Receiver, {:package_delivered, package})
    deliver(remaining_packages)
  end

  defp make_delivery do
    :rand.uniform(1_000)
    |> :timer.sleep()
    maybe_crash()
  end

  defp maybe_crash do
    crash_factor = :rand.uniform(100)
    IO.puts("Crash factor #{crash_factor}")
    if crash_factor > 60, do: raise("oh no! going down!")
  end
end
