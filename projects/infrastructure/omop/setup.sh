#!/usr/bin/env bash
set -euo pipefail

# OMOP CDM Setup Script

echo "=== OMOP CDM Setup ==="

mkdir -p ddl/{postgresql,sqlite} vocab data

# Download DDL files
DDL_BASE="https://raw.githubusercontent.com/OHDSI/CommonDataModel/main/inst/ddl/5.4"

echo "Downloading OMOP CDM 5.4 DDL files..."

if [[ ! -f "ddl/postgresql/OMOPCDM_postgresql_5.4_ddl.sql" ]]; then
    curl -sL "$DDL_BASE/postgresql/OMOPCDM_postgresql_5.4_ddl.sql" \
        -o ddl/postgresql/OMOPCDM_postgresql_5.4_ddl.sql
    echo "Downloaded PostgreSQL DDL"
fi

# Create SQLite version (simplified)
if [[ ! -f "ddl/sqlite/OMOPCDM_sqlite_5.4_ddl.sql" ]]; then
    # SQLite DDL needs manual adaptation; provide placeholder
    cat > ddl/sqlite/README.md << 'EOF'
# SQLite DDL

OMOP CDM DDL needs adaptation for SQLite.

Options:
1. Use the ohdsi-sqlite package: https://github.com/AustralianCancerDataNetwork/ohdsi-sqlite
2. Manually convert PostgreSQL DDL (remove CONSTRAINT syntax, etc.)
3. Use DuckDB which has better SQL compatibility

For development/testing, consider DuckDB:
```python
import duckdb
con = duckdb.connect('omop.duckdb')
# DuckDB supports most PostgreSQL syntax
```
EOF
    echo "Created SQLite README"
fi

if [[ ! -d "venv" ]]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Download vocabularies from https://athena.ohdsi.org/"
echo "2. Extract to vocab/"
echo "3. Create database and load DDL"
echo "4. Load vocabularies"
echo ""
echo "See README.md for details."
