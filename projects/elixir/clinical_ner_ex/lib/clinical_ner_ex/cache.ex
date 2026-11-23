defmodule ClinicalNerEx.Cache do
  @moduledoc """
  ETS-based cache for patterns, dictionaries, and linking results.

  This GenServer owns the ETS tables used for caching:

  - `:patterns_cache` - Compiled regex patterns and pattern configurations
  - `:dictionaries_cache` - Drug names, lab names, etc.
  - `:linker_cache` - Ontology linking results

  ## Usage

      # Get a cached value
      {:ok, value} = ClinicalNerEx.Cache.get(:patterns_cache, :medication_patterns)

      # Put a value in cache
      :ok = ClinicalNerEx.Cache.put(:dictionaries_cache, :drug_names, drug_list)

      # Clear a cache
      :ok = ClinicalNerEx.Cache.clear(:linker_cache)

      # Check if a drug name is known
      true = ClinicalNerEx.Cache.is_known_drug?("metformin")

  ## Pattern Files

  Pattern files are loaded from `priv/patterns/*.json` and contain regex patterns
  for rule-based extraction.

  ## Dictionary Files

  Dictionary files are loaded from `priv/dictionaries/*.txt` and contain lists
  of known entities (drug names, lab names, etc.).
  """

  use GenServer

  require Logger

  @tables [:patterns_cache, :dictionaries_cache, :linker_cache]

  # Client API

  @doc """
  Starts the Cache GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a value from the cache.

  ## Examples

      iex> ClinicalNerEx.Cache.get(:patterns_cache, :medication_patterns)
      {:ok, [...]}

      iex> ClinicalNerEx.Cache.get(:patterns_cache, :nonexistent)
      :miss
  """
  @spec get(atom(), term()) :: {:ok, term()} | :miss
  def get(table, key) when table in @tables do
    case :ets.lookup(table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :miss
    end
  rescue
    ArgumentError -> :miss
  end

  @doc """
  Puts a value in the cache.

  ## Examples

      iex> ClinicalNerEx.Cache.put(:patterns_cache, :my_pattern, ~r/test/)
      :ok
  """
  @spec put(atom(), term(), term()) :: :ok
  def put(table, key, value) when table in @tables do
    :ets.insert(table, {key, value})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Clears all entries from a cache table.

  ## Examples

      iex> ClinicalNerEx.Cache.clear(:linker_cache)
      :ok
  """
  @spec clear(atom()) :: :ok
  def clear(table) when table in @tables do
    :ets.delete_all_objects(table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Returns all cache table names.
  """
  @spec tables() :: [atom()]
  def tables, do: @tables

  @doc """
  Gets the set of known drug names from the cache.

  Returns a MapSet of lowercase drug names, or an empty MapSet if not loaded.

  ## Examples

      iex> drug_names = ClinicalNerEx.Cache.get_drug_names()
      iex> MapSet.member?(drug_names, "metformin")
      true
  """
  @spec get_drug_names() :: MapSet.t()
  def get_drug_names do
    case get(:dictionaries_cache, :drug_names) do
      {:ok, names} -> names
      :miss -> MapSet.new()
    end
  end

  @doc """
  Checks if a drug name is in the known drug names dictionary.

  The check is case-insensitive.

  ## Examples

      iex> ClinicalNerEx.Cache.is_known_drug?("metformin")
      true

      iex> ClinicalNerEx.Cache.is_known_drug?("METFORMIN")
      true

      iex> ClinicalNerEx.Cache.is_known_drug?("notarealmedication")
      false
  """
  @spec is_known_drug?(String.t()) :: boolean()
  def is_known_drug?(name) when is_binary(name) do
    drug_names = get_drug_names()
    MapSet.member?(drug_names, String.downcase(name))
  end

  @doc """
  Gets medication patterns from the cache.

  Returns the parsed JSON patterns, or nil if not loaded.

  ## Examples

      iex> {:ok, patterns} = ClinicalNerEx.Cache.get_medication_patterns()
      iex> patterns["version"]
      "1.0"
  """
  @spec get_medication_patterns() :: {:ok, map()} | :miss
  def get_medication_patterns do
    get(:patterns_cache, :medications)
  end

  @doc """
  Reloads all patterns and dictionaries from disk.

  Useful for updating cached data without restarting the application.

  ## Examples

      iex> ClinicalNerEx.Cache.reload()
      :ok
  """
  @spec reload() :: :ok
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables
    Enum.each(@tables, fn table ->
      :ets.new(table, [:set, :public, :named_table, read_concurrency: true])
    end)

    # Load patterns and dictionaries
    load_patterns()
    load_dictionaries()

    {:ok, %{}}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    load_patterns()
    load_dictionaries()
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("ClinicalNerEx.Cache received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp load_patterns do
    Logger.debug("Loading patterns into cache")

    # Load medication patterns
    load_pattern_file("medications.json", :medications)
  end

  defp load_pattern_file(filename, cache_key) do
    pattern_file = priv_path("patterns/#{filename}")

    with true <- File.exists?(pattern_file),
         {:ok, content} <- File.read(pattern_file),
         {:ok, patterns} <- Jason.decode(content) do
      put(:patterns_cache, cache_key, patterns)
      Logger.debug("Loaded patterns from #{filename}")
    else
      false ->
        Logger.debug("Pattern file not found: #{pattern_file}")

      {:error, reason} ->
        Logger.warning("Failed to load #{filename}: #{inspect(reason)}")
    end
  end

  defp load_dictionaries do
    Logger.debug("Loading dictionaries into cache")

    # Load drug names dictionary
    load_dictionary_file("drug_names.txt", :drug_names)
  end

  defp load_dictionary_file(filename, cache_key) do
    dict_file = priv_path("dictionaries/#{filename}")

    with true <- File.exists?(dict_file),
         {:ok, content} <- File.read(dict_file) do
      names = parse_dictionary_content(content)
      put(:dictionaries_cache, cache_key, names)
      Logger.debug("Loaded #{MapSet.size(names)} entries from #{filename}")
    else
      false ->
        Logger.debug("Dictionary file not found: #{dict_file}")

      {:error, reason} ->
        Logger.warning("Failed to read #{filename}: #{inspect(reason)}")
    end
  end

  defp parse_dictionary_content(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(String.starts_with?(&1, "#") or &1 == ""))
    |> Enum.map(&String.downcase/1)
    |> MapSet.new()
  end

  defp priv_path(relative_path) do
    case :code.priv_dir(:clinical_ner_ex) do
      {:error, _} ->
        # Fallback for development/test
        Path.join(["priv", relative_path])

      priv_dir ->
        Path.join(priv_dir, relative_path)
    end
  end
end
