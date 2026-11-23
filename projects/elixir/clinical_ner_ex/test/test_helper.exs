ExUnit.start()

# Define any mocks
Mox.defmock(ClinicalNerEx.OntologyMock, for: ClinicalNerEx.Extractors.Behaviour)
