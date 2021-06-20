[[34m2021-06-20 14:12:46,110[0m] {[34mpysolr.py:[0m382} INFO[0m - Finished 'http://localhost:8983/solr/ckan/select/?q=%2A%3A%2A&rows=1&wt=json' (get) with body '' in 0.006 seconds, with status 200[0m
/*
This script configures the permissions for the datastore.

It ensures that the datastore read-only user will only be able to select from
the datastore database but has no create/write/edit permission or any
permissions on other databases. You must execute this script as a database
superuser on the PostgreSQL server that hosts your datastore database.

For example, if PostgreSQL is running locally and the "postgres" user has the
appropriate permissions (as in the default Ubuntu PostgreSQL install), you can
run:

    ckan -c /etc/ckan/default/ckan.ini datastore set-permissions | sudo -u postgres psql

Or, if your PostgreSQL server is remote, you can pipe the permissions script
over SSH:

    ckan -c /etc/ckan/default/ckan.ini datastore set-permissions | ssh dbserver sudo -u postgres psql

*/

-- Most of the following commands apply to an explicit database or to the whole
-- 'public' schema, and could be executed anywhere. But ALTER DEFAULT
-- PERMISSIONS applies to the current database, and so we must be connected to
-- the datastore DB:
\connect "datastore"

-- revoke permissions for the read-only user
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE USAGE ON SCHEMA public FROM PUBLIC;

GRANT CREATE ON SCHEMA public TO "sandang";
GRANT USAGE ON SCHEMA public TO "sandang";

GRANT CREATE ON SCHEMA public TO "sandang";
GRANT USAGE ON SCHEMA public TO "sandang";

-- take connect permissions from main db
REVOKE CONNECT ON DATABASE "ckan" FROM "datastore_ro";

-- grant select permissions for read-only user
GRANT CONNECT ON DATABASE "datastore" TO "datastore_ro";
GRANT USAGE ON SCHEMA public TO "datastore_ro";

-- grant access to current tables and views to read-only user
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "datastore_ro";

-- grant access to new tables and views by default
ALTER DEFAULT PRIVILEGES FOR USER "sandang" IN SCHEMA public
   GRANT SELECT ON TABLES TO "datastore_ro";

-- a view for listing valid table (resource id) and view names
CREATE OR REPLACE VIEW "_table_metadata" AS
    SELECT DISTINCT
        substr(md5(dependee.relname || COALESCE(dependent.relname, '')), 0, 17) AS "_id",
        dependee.relname AS name,
        dependee.oid AS oid,
        dependent.relname AS alias_of
    FROM
        pg_class AS dependee
        LEFT OUTER JOIN pg_rewrite AS r ON r.ev_class = dependee.oid
        LEFT OUTER JOIN pg_depend AS d ON d.objid = r.oid
        LEFT OUTER JOIN pg_class AS dependent ON d.refobjid = dependent.oid
    WHERE
        (dependee.oid != dependent.oid OR dependent.oid IS NULL) AND
        -- is a table (from pg_tables view definition)
        -- or is a view (from pg_views view definition)
        (dependee.relkind = 'r'::"char" OR dependee.relkind = 'v'::"char")
        AND dependee.relnamespace = (
            SELECT oid FROM pg_namespace WHERE nspname='public')
    ORDER BY dependee.oid DESC;
ALTER VIEW "_table_metadata" OWNER TO "sandang";
GRANT SELECT ON "_table_metadata" TO "datastore_ro";

-- _full_text fields are now updated by a trigger when set to NULL
CREATE OR REPLACE FUNCTION populate_full_text_trigger() RETURNS trigger
AS $body$
    BEGIN
        IF NEW._full_text IS NOT NULL THEN
            RETURN NEW;
        END IF;
        NEW._full_text := (
            SELECT to_tsvector(string_agg(value, ' '))
            FROM json_each_text(row_to_json(NEW.*))
            WHERE key NOT LIKE '\_%');
        RETURN NEW;
    END;
$body$ LANGUAGE plpgsql;
ALTER FUNCTION populate_full_text_trigger() OWNER TO "sandang";

-- migrate existing tables that don't have full text trigger applied
DO $body$
    BEGIN
        EXECUTE coalesce(
            (SELECT string_agg(
                'CREATE TRIGGER zfulltext BEFORE INSERT OR UPDATE ON ' ||
                quote_ident(relname) || ' FOR EACH ROW EXECUTE PROCEDURE ' ||
                'populate_full_text_trigger();', ' ')
            FROM pg_class
            LEFT OUTER JOIN pg_trigger AS t
                ON t.tgrelid = relname::regclass AND t.tgname = 'zfulltext'
            WHERE relkind = 'r'::"char" AND t.tgname IS NULL
                AND relnamespace = (
                    SELECT oid FROM pg_namespace WHERE nspname='public')),
            'SELECT 1;');
    END;
$body$;

