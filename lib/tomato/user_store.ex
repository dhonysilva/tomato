defmodule Tomato.UserStore do
  use Agent

  def start_link(_opts), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  def get(user_id), do: Agent.get(__MODULE__, &Map.get(&1, user_id))

  def put(user_id, display_name, has_custom_name) do
    Agent.update(__MODULE__, &Map.put(&1, user_id, %{
      display_name: display_name,
      has_custom_name: has_custom_name
    }))
  end
end
