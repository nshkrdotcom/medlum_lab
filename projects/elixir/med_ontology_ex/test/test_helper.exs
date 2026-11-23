ExUnit.start()

# Define Mox mock for Snowstorm client (SNOMED-CT)
Mox.defmock(MedOntology.Client.SnowstormMock, for: MedOntology.Client)

# Define Mox mock for RxNav client (RxNorm)
# Uses RxNavBehaviour which includes additional RxNorm-specific callbacks
Mox.defmock(MedOntology.Client.RxNavMock, for: MedOntology.Client.RxNavBehaviour)

# Define Mox mock for LOINC client
# Uses LOINCBehaviour which includes additional LOINC-specific callbacks
Mox.defmock(MedOntology.Client.LOINCMock, for: MedOntology.Client.LOINCBehaviour)

# Set up the test environment to use the mock clients
Application.put_env(:med_ontology_ex, :snowstorm_client, MedOntology.Client.SnowstormMock)
Application.put_env(:med_ontology_ex, :rxnav_client, MedOntology.Client.RxNavMock)
Application.put_env(:med_ontology_ex, :loinc_client, MedOntology.Client.LOINCMock)

# Ensure cache directory exists for tests
cache_dir = System.tmp_dir!() |> Path.join("med_ontology_test_cache")
File.mkdir_p!(cache_dir)
Application.put_env(:med_ontology_ex, :cache_dir, cache_dir)
