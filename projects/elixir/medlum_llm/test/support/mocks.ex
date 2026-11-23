# Define mocks for NSAI libraries
#
# These mocks allow testing MedlumLlm functionality without requiring
# the actual NSAI libraries to be running or available.
#
# Usage in tests:
#
#     import Mox
#     setup :verify_on_exit!
#
#     test "loads dataset" do
#       expect(HfDatasetsExMock, :load_dataset, fn _repo, _opts ->
#         {:ok, [%{question: "test", answer: "A"}]}
#       end)
#
#       {:ok, _ds} = MedlumLlm.Datasets.load(:medqa)
#     end

# Note: These mocks require behaviours to be defined in the NSAI libraries.
# If behaviours are not available, you may need to define simple stub modules
# instead of using Mox.

# Mox.defmock(HfDatasetsExMock, for: HfDatasetsEx.Behaviour)
# Mox.defmock(EvalExMetricsMock, for: EvalEx.Metrics.Behaviour)
# Mox.defmock(CrucibleBenchMock, for: CrucibleBench.Behaviour)

# Simple stub modules for testing when behaviours are not available
defmodule HfDatasetsExMock do
  @moduledoc false

  def load_dataset(_repo, _opts \\ []) do
    {:ok, []}
  end
end

defmodule EvalExMock do
  @moduledoc false

  def accuracy(_predictions, _samples) do
    1.0
  end

  def f1(_predictions, _samples, _opts \\ []) do
    1.0
  end
end

defmodule CrucibleBenchMock do
  @moduledoc false

  def run(_experiment, _opts \\ []) do
    {:ok, %{}}
  end
end

defmodule CrucibleHarnessMock do
  @moduledoc false

  def run(_experiment, _opts \\ []) do
    {:ok, %{}}
  end
end

defmodule CrucibleEnsembleMock do
  @moduledoc false

  def vote(_responses, _strategy \\ :majority) do
    {:ok, %{answer: "A", consensus: 1.0}}
  end
end
