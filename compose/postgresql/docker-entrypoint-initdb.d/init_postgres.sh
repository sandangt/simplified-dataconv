#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE ROLE $DS_RO_USER NOSUPERUSER NOCREATEDB NOCREATEROLE LOGIN PASSWORD '$DS_RO_PASS';
    CREATE DATABASE $DS_DB OWNER $POSTGRES_USER ENCODING 'utf-8';
    GRANT ALL PRIVILEGES ON DATABASE $DS_DB TO $POSTGRES_USER;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE ROLE $AIRFLOW_USER NOSUPERUSER CREATEDB CREATEROLE LOGIN PASSWORD '$AIRFLOW_PASSWORD'; 
    CREATE DATABASE $AIRFLOW_DB OWNER $AIRFLOW_USER ENCODING 'utf-8';
    GRANT ALL PRIVILEGES ON DATABASE $AIRFLOW_DB TO $AIRFLOW_USER;
EOSQL