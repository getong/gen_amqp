defmodule ServerDemo do
  @moduledoc false

  use GenAMQP.Server, event: "demo"

  def execute(_) do
    {:reply, "ok"}
  end
end

defmodule DemoApp do
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # Define supervisors and child supervisors to be supervised
    children = [
      supervisor(ServerDemo, []),
    ]

    opts = [strategy: :one_for_one, name: Core.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
