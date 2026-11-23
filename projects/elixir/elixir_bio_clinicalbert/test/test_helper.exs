ExUnit.start()

# Define mocks
Mox.defmock(ElixirBioClinicalbert.EmbedderMock, for: ElixirBioClinicalbert.Embedder)
