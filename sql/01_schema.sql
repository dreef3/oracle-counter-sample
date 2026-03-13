-- =============================================================
-- 01_schema.sql
-- Creates the report number sequence tracker table.
-- =============================================================

WHENEVER SQLERROR EXIT FAILURE ROLLBACK;

-- Drop existing table so the script is re-runnable in CI
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE report_number_seq PURGE';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -942 THEN   -- -942 = table/view does not exist
            RAISE;
        END IF;
END;
/

CREATE TABLE report_number_seq (
    account_number  VARCHAR2(50)  NOT NULL,
    format          VARCHAR2(50)  NOT NULL,
    output_channel  VARCHAR2(50)  NOT NULL,
    report_date     DATE          NOT NULL,
    last_number     NUMBER(10)    DEFAULT 0 NOT NULL,
    CONSTRAINT pk_report_number_seq
        PRIMARY KEY (account_number, format, output_channel, report_date)
);

COMMIT;

PROMPT Schema created successfully.
